import AVFoundation
import Defaults
import Foundation
import MusicSearchKit
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
        var fileExtension: String
        var size: Int64
        var lastUsed: Date

        var id: String { key }
    }

    /// Everything cached, by key.
    private(set) var entries: [String: Entry] = [:]
    /// Keys being fetched right now.
    private(set) var inFlight: Set<String> = []

    /// How many songs to keep, as chosen. Zero turns the cache off. Without
    /// Cue Super the cache keeps `freeSongLimit` at most whatever this says
    /// (`effectiveSongLimit`), and the choice is kept for when Super comes.
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

    /// The most songs the cache keeps without Cue Super: the free download
    /// limit's, since cached songs play with no network as downloads do.
    static let freeSongLimit = 50

    /// How many songs the cache keeps now: `songLimit`, held to
    /// `freeSongLimit` without Super (`GatedFeature.largePlaybackCache`).
    /// Read as the cache trims, so a lapsed Super lets the extra go as
    /// songs next come in.
    var effectiveSongLimit: Int {
        FeatureGate.shared.isAvailable(.largePlaybackCache) ? songLimit : min(songLimit, Self.freeSongLimit)
    }

    var totalBytes: Int64 {
        entries.values.reduce(0) { $0 + $1.size }
    }

    /// Songs coming down, by key: the queue's next ones, and any the player
    /// is reading from (`streamingAsset(for:from:)`).
    @ObservationIgnored private var downloads: [String: SongDownload] = [:]
    /// How many player items read each song's download. A song read keeps
    /// its download, and goes first, whatever the queue says.
    @ObservationIgnored private var readers: [String: Int] = [:]
    @ObservationIgnored private var pending: [String: PlayableContent] = [:]
    /// Keys the queue wants next, kept clear of eviction.
    @ObservationIgnored private var wanted: [String] = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// The iCloud songs coming up, kept clear of eviction.
    @ObservationIgnored private var cloudWanted: Set<String> = []
    @ObservationIgnored private let pathMonitor = NWPathMonitor()

    /// How many songs come down at once. Plex turns away more than a couple
    /// of requests at a time from one client.
    private static let concurrentDownloads = 2

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
        Self.removePartialFiles()
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
        entry.fileExtension = DownloadManager.containerFixed(key: key, fileExtension: entry.fileExtension, in: Self.fileURL)
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
        // A book's files run for hours: fetched whole ahead of time they'd
        // fill the cache with one book, and the player streams them fine.
        let books = AudiobookPlayer.shared
        let cacheable = window.filter { manager.canDownload($0) && !manager.isDownloaded($0) && !books.contains($0) }
        wanted = cacheable.map { DownloadManager.key(for: $0) }

        // Fetches for songs no longer coming up are wasted bytes.
        for (key, download) in downloads where !wanted.contains(key) && readers[key] == nil {
            SongDownload.queue.async { download.cancel() }
            downloads[key] = nil
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
        while streamedCloudIDs.count > effectiveSongLimit, !evictable.isEmpty {
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
        guard !inFlight.contains(key), let url = item.playbackStreamURL else { return }
        if let entry = entries[key],
           FileManager.default.fileExists(atPath: Self.fileURL(key: key, fileExtension: entry.fileExtension).path) {
            return
        }
        startDownload(of: item, key: key, from: url)
        admit()
    }

    @discardableResult
    private func startDownload(of item: PlayableContent, key: String, from url: URL) -> SongDownload {
        let fileExtension = Self.fileExtension(for: item, url: url)
        let destination = Self.fileURL(key: key, fileExtension: fileExtension)
        inFlight.insert(key)
        pending[key] = item
        let download = SongDownload(
            key: key,
            remote: url,
            fileExtension: fileExtension,
            partURL: destination.appendingPathExtension(Self.partExtension),
            destination: destination,
            allowsCellular: allowsCellular
        ) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let size):
                    self?.fetchFinished(key: key, fileExtension: fileExtension, size: size, destination: destination)
                case .failure:
                    self?.fetchFailed(key: key)
                }
            }
        }
        downloads[key] = download
        return download
    }

    /// Runs the songs that matter most, a couple at a time — those the
    /// player is reading first, then the queue's order — and pauses the
    /// rest, which pick up where they stopped when their turn comes.
    private func admit() {
        let order = readers.keys.filter { downloads[$0] != nil }.sorted { (wanted.firstIndex(of: $0) ?? 0) < (wanted.firstIndex(of: $1) ?? 0) }
            + wanted.filter { downloads[$0] != nil && readers[$0] == nil }
        let running = Set(order.prefix(Self.concurrentDownloads))
        for (key, download) in downloads {
            let runs = running.contains(key)
            SongDownload.queue.async { runs ? download.run() : download.pause() }
        }
    }

    /// The song's file as it comes down, for the player to read instead of
    /// fetching it again itself, or nil when the cache doesn't keep this
    /// song (books, Files, the cache off, a converted stream, cellular when
    /// the cache isn't to use it) and the player streams it as before. A
    /// converted stream has no length up front, which reading by range
    /// needs.
    func streamingAsset(for item: PlayableContent, from url: URL) -> AVURLAsset? {
        let key = DownloadManager.key(for: item)
        guard isEnabled, DeviceStream.isTranscodable(item.content.service),
              StreamTranscoding.format(for: .device) == .original,
              DownloadManager.shared.canDownload(item), !DownloadManager.shared.isDownloaded(item),
              !AudiobookPlayer.shared.contains(item), entries[key] == nil,
              allowsCellular || !isOnExpensivePath else { return nil }
        let download = downloads[key] ?? startDownload(of: item, key: key, from: url)
        let released: @MainActor () -> Void = { [weak self] in self?.readerLeft(key) }
        guard let asset = CachingStreamLoader.makeAsset(for: download, remote: url, released: released) else { return nil }
        readers[key, default: 0] += 1
        // A song being played comes down over cellular too: the player
        // would have streamed it over cellular anyway.
        SongDownload.queue.async {
            if !download.allowsCellular {
                download.allowsCellular = true
                download.pause()
            }
        }
        admit()
        return asset
    }

    /// A player item reading a song's download is gone. Once nothing reads
    /// it and the queue doesn't want it, the download goes too.
    private func readerLeft(_ key: String) {
        readers[key, default: 1] -= 1
        if readers[key] ?? 0 <= 0 {
            readers[key] = nil
            if !wanted.contains(key), let download = downloads.removeValue(forKey: key) {
                SongDownload.queue.async { download.cancel() }
                inFlight.remove(key)
                pending[key] = nil
            }
        }
        admit()
    }

    private static let partExtension = "part"

    private func fetchFinished(key: String, fileExtension: String, size: Int64, destination: URL) {
        inFlight.remove(key)
        downloads[key] = nil
        admit()
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
        downloads[key] = nil
        pending[key] = nil
        admit()
    }

    /// Evicts the least recently played beyond the cap, never anything the
    /// queue wants next.
    private func trim() {
        let limit = effectiveSongLimit
        guard limit >= 0 else { return }
        var evictable = entries.values
            .filter { !wanted.contains($0.key) }
            .sorted { $0.lastUsed < $1.lastUsed }
        while entries.count > limit, let victim = evictable.first {
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
        for download in downloads.values {
            SongDownload.queue.async { download.cancel() }
        }
        downloads = [:]
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

    /// What a download left half done when the app last quit.
    private static func removePartialFiles() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(".\(partExtension)") {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
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
