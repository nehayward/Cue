import Defaults
import Foundation
import Network
import Observation
import SonosKit

/// A rolling cache for on-device playback: the next few songs in the local
/// queue are fetched ahead of time, and recently played ones are kept, up to
/// a set number, so a tunnel or a dead spot on the commute passes in
/// silence's opposite. Separate from Downloads — nothing here was asked for
/// by name, and the least recently played goes first when the cap is hit.
///
/// Covers Plex and Subsonic, whose songs stream from the user's own server.
/// A Files folder in iCloud Drive is streamed the only way iCloud allows:
/// upcoming songs are asked of iCloud ahead of time — further ahead than
/// the server window, since a file has to land whole before it can play —
/// and once they drop out of the cache they are evicted from the device
/// again, so the folder can live in iCloud with a rolling window here.
/// Songs the user downloaded by name are never evicted.
///
/// Files live in Application Support/PlaybackCache, excluded from backups.
@MainActor
@Observable
final class PlaybackCache {
    static let shared = PlaybackCache()

    struct Entry: Codable, Identifiable, Hashable, Sendable {
        let key: String
        let title: String
        let subtitle: String
        let fileExtension: String
        var size: Int64
        var lastUsed: Date

        var id: String { key }
    }

    /// Everything cached, by key.
    private(set) var entries: [String: Entry] = [:]
    /// Keys being fetched right now.
    private(set) var inFlight: Set<String> = []

    /// How many songs to keep. Zero turns the cache off.
    var songLimit: Int {
        didSet {
            UserDefaults.standard.set(songLimit, forKey: AppStorageKeys.playbackCacheSongLimit)
            trim()
            trimCloud()
        }
    }

    /// How many upcoming songs to fetch ahead of the one playing.
    var prefetchCount: Int {
        didSet { UserDefaults.standard.set(prefetchCount, forKey: AppStorageKeys.playbackCachePrefetchCount) }
    }

    /// Whether to fill over cellular. On by default: the commute is the
    /// whole point.
    var allowsCellular: Bool {
        didSet { UserDefaults.standard.set(allowsCellular, forKey: AppStorageKeys.playbackCacheOverCellular) }
    }

    /// Whether an iCloud Drive folder is streamed — fetched ahead and
    /// evicted behind — or upcoming songs are simply downloaded and kept.
    var streamsFromCloud: Bool {
        didSet {
            UserDefaults.standard.set(streamsFromCloud, forKey: AppStorageKeys.filesStreamFromCloud)
            if !streamsFromCloud {
                // What's here stays; it's just no longer ours to evict.
                streamedCloudIDs = []
                saveStreamed()
            }
        }
    }

    /// How far ahead to ask iCloud, in songs. Wider than `prefetchCount`:
    /// a server song plays as it arrives, an iCloud one only once it has
    /// arrived whole.
    static let cloudPrefetchCount = 8

    /// The iCloud songs fetched to play, oldest first. Bounded by
    /// `songLimit` like the server copies; the user's own downloads are
    /// tracked by `FilesLibraryService.keptTrackIDs` instead.
    private(set) var streamedCloudIDs: [String]

    /// Whether the current network is metered — cellular, or a hotspot.
    private(set) var isOnExpensivePath = false

    var isEnabled: Bool { songLimit > 0 }

    var totalBytes: Int64 {
        entries.values.reduce(0) { $0 + $1.size }
    }

    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var pending: [String: PlayableContent] = [:]
    /// Keys the queue wants next, kept clear of eviction.
    @ObservationIgnored private var wanted: [String] = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// The iCloud songs coming up, kept clear of eviction.
    @ObservationIgnored private var cloudWanted: Set<String> = []
    @ObservationIgnored private let pathMonitor = NWPathMonitor()

    @ObservationIgnored private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.timeoutIntervalForResource = 30 * 60
        return URLSession(configuration: configuration)
    }()

    private init() {
        let defaults = UserDefaults.standard
        songLimit = defaults.object(forKey: AppStorageKeys.playbackCacheSongLimit) == nil
            ? 50 : defaults.integer(forKey: AppStorageKeys.playbackCacheSongLimit)
        prefetchCount = defaults.object(forKey: AppStorageKeys.playbackCachePrefetchCount) == nil
            ? 3 : defaults.integer(forKey: AppStorageKeys.playbackCachePrefetchCount)
        allowsCellular = defaults.object(forKey: AppStorageKeys.playbackCacheOverCellular) == nil
            ? true : defaults.bool(forKey: AppStorageKeys.playbackCacheOverCellular)
        streamsFromCloud = defaults.object(forKey: AppStorageKeys.filesStreamFromCloud) == nil
            ? true : defaults.bool(forKey: AppStorageKeys.filesStreamFromCloud)
        streamedCloudIDs = defaults.stringArray(forKey: AppStorageKeys.playbackCacheCloudIDs) ?? []
        Self.prepareDirectory()
        entries = Self.loadManifest()
        reconcileWithDisk()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let expensive = path.isExpensive || path.isConstrained
            Task { @MainActor in self?.isOnExpensivePath = expensive }
        }
        pathMonitor.start(queue: DispatchQueue(label: "dance.cue.playbackcache.path", qos: .utility))
    }

    // MARK: - Reading

    /// The cached copy of a song, or nil. Reading it counts as a play for
    /// the eviction order.
    func localURL(for item: PlayableContent) -> URL? {
        let key = DownloadManager.key(for: item)
        guard var entry = entries[key] else { return nil }
        let url = Self.fileURL(key: key, fileExtension: entry.fileExtension)
        guard FileManager.default.fileExists(atPath: url.path) else {
            entries[key] = nil
            return nil
        }
        entry.lastUsed = .now
        entries[key] = entry
        scheduleSave()
        return url
    }

    func isCached(_ item: PlayableContent) -> Bool {
        entries[DownloadManager.key(for: item)] != nil
    }

    // MARK: - Filling

    /// Called by the local player whenever its queue or position changes:
    /// the song playing and the next few are wanted, whatever else is not.
    func queueDidChange(_ queue: [PlayableContent], currentIndex: Int) {
        guard isEnabled else { return }
        let start = max(0, min(currentIndex, queue.count))
        let window = Array(queue.dropFirst(start).prefix(prefetchCount + 1))

        fillFromCloud(queue: queue, start: start)

        let manager = DownloadManager.shared
        let cacheable = window.filter { manager.canDownload($0) && !manager.isDownloaded($0) }
        wanted = cacheable.map { DownloadManager.key(for: $0) }

        // Fetches for songs no longer coming up are wasted bytes.
        for (key, task) in tasks where !wanted.contains(key) {
            task.cancel()
            tasks[key] = nil
            inFlight.remove(key)
            pending[key] = nil
        }
        for item in cacheable {
            fetch(item)
        }
        trim()
    }

    // MARK: - iCloud Drive

    /// Asks iCloud for the Files songs coming up, and evicts the streamed
    /// ones that have dropped behind.
    private func fillFromCloud(queue: [PlayableContent], start: Int) {
        let files = FilesLibraryService.shared
        guard files.isConfigured, files.isCloudFolder else { return }

        let reach = streamsFromCloud ? Self.cloudPrefetchCount : prefetchCount
        let upcoming = queue.dropFirst(start).prefix(reach + 1).filter { $0.content.service == .files }
        guard !upcoming.isEmpty else {
            cloudWanted = []
            trimCloud()
            return
        }

        // The song about to play is needed whatever the network is; the
        // ones behind it wait for Wi-Fi when cellular is off.
        let fetchable = allowsCellular || !isOnExpensivePath
            ? Array(upcoming)
            : upcoming.filter { $0.content.id == queue[start].content.id }
        let ids = fetchable
            .filter { files.cloudStatus(trackID: $0.content.id) == .notDownloaded }
            .map(\.content.id)
        if !ids.isEmpty {
            files.downloadFromCloud(trackIDs: ids, keep: !streamsFromCloud)
        }

        guard streamsFromCloud else { return }
        cloudWanted = Set(upcoming.map(\.content.id))
        // Only what this cache fetched is its to evict: a song that was
        // already here — downloaded before streaming existed, say — is
        // never adopted. Fetched now, or played again, goes to the back of
        // the eviction order.
        let playing = upcoming.first.map(\.content.id)
        for id in ids + (playing.map { streamedCloudIDs.contains($0) ? [$0] : [] } ?? []) {
            streamedCloudIDs.removeAll { $0 == id }
            streamedCloudIDs.append(id)
        }
        trimCloud()
    }

    /// Evicts the oldest streamed iCloud copies beyond the cap, never one
    /// coming up, never one the user kept.
    private func trimCloud() {
        guard streamsFromCloud else { return }
        let files = FilesLibraryService.shared
        streamedCloudIDs.removeAll { files.isKept(trackID: $0) }
        var evictable = streamedCloudIDs.filter { !cloudWanted.contains($0) }
        while streamedCloudIDs.count > songLimit, !evictable.isEmpty {
            let victim = evictable.removeFirst()
            files.evictStreamed(trackIDs: [victim])
            streamedCloudIDs.removeAll { $0 == victim }
        }
        saveStreamed()
    }

    private func saveStreamed() {
        UserDefaults.standard.set(streamedCloudIDs, forKey: AppStorageKeys.playbackCacheCloudIDs)
    }

    // MARK: - Server streams

    private func fetch(_ item: PlayableContent) {
        let key = DownloadManager.key(for: item)
        // Under the cache's own Plex session: the player may be streaming
        // this very song, and a transcode started under its session would
        // end that stream.
        guard !inFlight.contains(key), let url = item.deviceStreamURL(for: .cache) else { return }
        if let entry = entries[key],
           FileManager.default.fileExists(atPath: Self.fileURL(key: key, fileExtension: entry.fileExtension).path) {
            return
        }

        var request = URLRequest(url: url)
        request.allowsCellularAccess = allowsCellular
        request.allowsExpensiveNetworkAccess = allowsCellular
        request.allowsConstrainedNetworkAccess = allowsCellular

        let fileExtension = Self.fileExtension(for: item, url: url)
        let destination = Self.fileURL(key: key, fileExtension: fileExtension)
        inFlight.insert(key)
        pending[key] = item

        let task = session.downloadTask(with: request) { [weak self] temporary, response, error in
            // The temporary file is gone once this returns: move it now, on
            // the session's queue, then report on the main actor. A refused
            // request (a 4xx page) is not a song to keep.
            guard let temporary, error == nil, StreamResponseCheck.refusal(in: response) == nil else {
                Task { @MainActor in self?.fetchFailed(key: key) }
                return
            }
            try? FileManager.default.removeItem(at: destination)
            let moved = (try? FileManager.default.moveItem(at: temporary, to: destination)) != nil
            let size = moved ? DownloadManager.size(of: destination) : nil
            Task { @MainActor in
                if moved {
                    self?.fetchFinished(key: key, fileExtension: fileExtension, size: size ?? 0, destination: destination)
                } else {
                    self?.fetchFailed(key: key)
                }
            }
        }
        // The song about to play is the one that matters most.
        task.priority = wanted.first == key ? URLSessionTask.highPriority : URLSessionTask.defaultPriority
        tasks[key] = task
        task.resume()
    }

    private func fetchFinished(key: String, fileExtension: String, size: Int64, destination: URL) {
        inFlight.remove(key)
        tasks[key] = nil
        let item = pending[key]
        pending[key] = nil
        entries[key] = Entry(
            key: key,
            title: item?.title ?? key,
            subtitle: item?.metadata?.artist ?? item?.subtitle ?? "",
            fileExtension: fileExtension,
            size: size,
            lastUsed: .now
        )
        scheduleSave()
        trim()
        if let item {
            LocalPlaybackService.shared.cachedCopyLanded(for: item, at: destination)
        }
    }

    private func fetchFailed(key: String) {
        inFlight.remove(key)
        tasks[key] = nil
        pending[key] = nil
    }

    /// Evicts the least recently played beyond the cap, never anything the
    /// queue wants next.
    private func trim() {
        guard songLimit >= 0 else { return }
        var evictable = entries.values
            .filter { !wanted.contains($0.key) }
            .sorted { $0.lastUsed < $1.lastUsed }
        while entries.count > songLimit, let victim = evictable.first {
            evictable.removeFirst()
            try? FileManager.default.removeItem(at: Self.fileURL(key: victim.key, fileExtension: victim.fileExtension))
            entries[victim.key] = nil
        }
        scheduleSave()
    }

    /// Empties the cache — the streamed iCloud copies too. Fetches in
    /// flight are dropped.
    func clear() {
        if !streamedCloudIDs.isEmpty {
            FilesLibraryService.shared.evictStreamed(trackIDs: streamedCloudIDs)
            streamedCloudIDs = []
            saveStreamed()
        }
        for task in tasks.values {
            task.cancel()
        }
        tasks = [:]
        inFlight = []
        pending = [:]
        for entry in entries.values {
            try? FileManager.default.removeItem(at: Self.fileURL(key: entry.key, fileExtension: entry.fileExtension))
        }
        entries = [:]
        scheduleSave()
    }

    // MARK: - Storage

    private static func fileExtension(for item: PlayableContent, url: URL) -> String {
        let fromMetadata = item.playbackFileExtension ?? ""
        if !fromMetadata.isEmpty, fromMetadata.count <= 5 { return fromMetadata }
        let fromURL = url.pathExtension.lowercased()
        return fromURL.isEmpty ? "mp3" : fromURL
    }

    nonisolated private static var directory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("PlaybackCache", isDirectory: true)
    }

    nonisolated private static func fileURL(key: String, fileExtension: String) -> URL {
        directory.appendingPathComponent(key).appendingPathExtension(fileExtension)
    }

    nonisolated private static var manifestURL: URL {
        directory.appendingPathComponent("manifest.json")
    }

    private static func prepareDirectory() {
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private static func loadManifest() -> [String: Entry] {
        guard let data = try? Data(contentsOf: manifestURL),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [:] }
        return Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func reconcileWithDisk() {
        for entry in entries.values {
            let url = Self.fileURL(key: entry.key, fileExtension: entry.fileExtension)
            if !FileManager.default.fileExists(atPath: url.path) {
                entries[entry.key] = nil
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            let snapshot = Array(self.entries.values)
            await Task.detached(priority: .utility) {
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                try? data.write(to: Self.manifestURL, options: .atomic)
            }.value
        }
    }
}
