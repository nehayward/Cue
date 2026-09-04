import Defaults
import Foundation
import Observation
import SonosKit

/// A rolling cache for on-device playback: the next few songs in the local
/// queue are fetched ahead of time, and recently played ones are kept, up to
/// a set number, so a tunnel or a dead spot on the commute passes in
/// silence's opposite. Separate from Downloads — nothing here was asked for
/// by name, and the least recently played goes first when the cap is hit.
///
/// Covers Plex and Subsonic, whose songs stream from the user's own server.
/// For a Files folder in iCloud Drive the same window of upcoming songs is
/// asked of iCloud instead, which keeps them itself.
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

    var isEnabled: Bool { songLimit > 0 }

    var totalBytes: Int64 {
        entries.values.reduce(0) { $0 + $1.size }
    }

    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var pending: [String: PlayableContent] = [:]
    /// Keys the queue wants next, kept clear of eviction.
    @ObservationIgnored private var wanted: [String] = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?

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
        Self.prepareDirectory()
        entries = Self.loadManifest()
        reconcileWithDisk()
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

        // iCloud Drive keeps its own copies; it only needs asking.
        let cloudIDs = window
            .filter { $0.content.service == .files && $0.metadata?.isPlayable == false }
            .map(\.content.id)
        if !cloudIDs.isEmpty {
            FilesLibraryService.shared.downloadFromCloud(trackIDs: cloudIDs)
        }

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

    private func fetch(_ item: PlayableContent) {
        let key = DownloadManager.key(for: item)
        guard !inFlight.contains(key), let url = item.previewURL else { return }
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

        let task = session.downloadTask(with: request) { [weak self] temporary, _, error in
            // The temporary file is gone once this returns: move it now, on
            // the session's queue, then report on the main actor.
            guard let temporary, error == nil else {
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

    /// Empties the cache. Fetches in flight are dropped too.
    func clear() {
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
        let fromMetadata = item.metadata?.audioCodec?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
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
