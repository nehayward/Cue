import Defaults
import Foundation
import Observation
import SonosKit
import SubscriptionKit
import UIKit

/// Downloads tracks from the user's own servers — Plex and Subsonic, whose
/// `previewURL` is a direct, self-authenticating URL to the media file — to
/// this device for offline playback, and keeps them.
///
/// Transfers run on a background `URLSession`: the system carries them on
/// after the app is suspended, or killed, and relaunches the app to finish
/// up (`AppDelegate` hands the completion handler in). Nothing is
/// discretionary and up to four run at once per host, so a whole album lands
/// as fast as the server can send it. A failed transfer keeps its resume
/// data and picks up where it stopped.
///
/// Files live in Application Support/Downloads as `<key>.<ext>`, protected
/// until first unlock and excluded from backups (they're re-downloadable).
/// The manifest beside them is what survives a relaunch; the session's own
/// tasks are matched back to it by their `taskDescription`.
@MainActor
@Observable
final class DownloadManager {
    static let shared = DownloadManager()

    struct Item: Codable, Identifiable, Hashable, Sendable {
        enum State: String, Codable, Sendable {
            case queued, downloading, paused, completed, failed
        }

        /// Filesystem-safe id, stable per track (see `key(for:)`).
        let key: String
        let service: MusicService
        let contentID: String
        let title: String
        let subtitle: String
        let artwork: URL?
        /// What the transfer fetches. For Plex and Subsonic this is the
        /// stream as Streaming Quality delivered it when the download was
        /// made — rebuilt from `sourceURL` on a retry, so a format the
        /// server refused can be changed and tried again.
        var url: URL
        var fileExtension: String
        let createdAt: Date
        var state: State
        var bytesReceived: Int64 = 0
        var bytesExpected: Int64 = 0
        var fileSize: Int64?
        var resumeData: Data?
        var error: String?
        /// The original file (`previewURL`) and its suffix, kept so `url`
        /// can be rebuilt under the setting in force. Absent on manifests
        /// from before Streaming Quality; those retry as they were.
        var sourceURL: URL?
        var audioCodec: String?

        /// Points `url` and `fileExtension` at the stream the current
        /// Streaming Quality setting delivers. A transfer part-way through
        /// keeps its URL: its resume data belongs to that request.
        mutating func applyStreamingQuality() {
            guard resumeData == nil, let sourceURL, DeviceStream.isTranscodable(service) else { return }
            let refreshed = DeviceStream.url(service: service, contentID: contentID, sourceURL: sourceURL, audioCodec: audioCodec)
            guard refreshed != url else { return }
            url = refreshed
            fileExtension = DeviceStream.fileExtension(service: service, audioCodec: audioCodec) ?? fileExtension
        }

        var id: String { key }

        var progress: Double {
            DownloadNaming.progress(received: bytesReceived, expected: bytesExpected)
        }

        var isActive: Bool {
            state == .queued || state == .downloading
        }
    }

    /// An album, playlist or artist the user downloaded whole: which tracks
    /// it stood for at the time, so the album can be badged, removed and
    /// listed as one thing rather than as its songs.
    struct Container: Codable, Identifiable, Hashable, Sendable {
        let key: String
        let service: MusicService
        let contentID: String
        let type: ContentType
        let title: String
        let subtitle: String
        let artwork: URL?
        let createdAt: Date
        var trackKeys: [String]

        var id: String { key }
    }

    /// How far along a container is, read off its tracks.
    enum ContainerState: Equatable {
        /// Every track is on the device.
        case downloaded
        /// Some track is still coming (or paused, or failed), with the
        /// fraction of the whole that has landed.
        case downloading(Double)
    }

    /// Every download, complete or not, by key.
    private(set) var items: [String: Item] = [:]

    /// Albums, playlists and artists downloaded whole, by container key.
    private(set) var containers: [String: Container] = [:]

    /// Whether transfers may use cellular data. Read when each task is
    /// made, so flipping it applies to what's queued next.
    var allowsCellular: Bool {
        didSet { UserDefaults.standard.set(allowsCellular, forKey: AppStorageKeys.downloadsOverCellular) }
    }

    /// The completion handler iOS gives the app when it relaunches it for
    /// this session's events; called once the delegate has drained them.
    @ObservationIgnored var backgroundCompletionHandler: (() -> Void)?

    @ObservationIgnored private let relay = DownloadSessionRelay()
    @ObservationIgnored private var lastProgressPublish: [String: Date] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    @ObservationIgnored private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        // Not discretionary: the user asked for these, so the system
        // shouldn't wait for power or Wi‑Fi on their behalf.
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.shouldUseExtendedBackgroundIdleMode = true
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        return URLSession(configuration: configuration, delegate: relay, delegateQueue: nil)
    }()

    nonisolated static let sessionIdentifier = "dance.cue.downloads"

    private init() {
        allowsCellular = UserDefaults.standard.bool(forKey: AppStorageKeys.downloadsOverCellular)
        Self.prepareDirectory()
        items = Self.loadManifest()
        containers = Self.loadContainerManifest()
        relay.manager = self
        adoptLegacyPlexDownloads()
        reconcileWithDisk()
        pruneContainers()
        reattachSessionTasks()
    }

    // MARK: - Queries

    var active: [Item] {
        items.values.filter { $0.state != .completed }.sorted { $0.createdAt < $1.createdAt }
    }

    var completed: [Item] {
        items.values.filter { $0.state == .completed }.sorted { $0.createdAt > $1.createdAt }
    }

    var completedBytes: Int64 {
        completed.reduce(0) { $0 + ($1.fileSize ?? 0) }
    }

    var hasActiveDownloads: Bool {
        items.values.contains { $0.isActive }
    }

    // MARK: - Free limit

    /// How many songs may be kept without Cue Super. It's a ceiling on what's
    /// held, not a lifetime allowance: every entry counts, finished or on its
    /// way, and removing one frees its slot. iCloud Drive downloads and the
    /// playback cache are the system's and the cache's own and don't count.
    nonisolated static let freeSongLimit = 50

    /// Songs held against the free limit.
    var heldCount: Int { items.count }

    /// Slots left before the free limit, or nil with Super, which has none.
    var remainingFreeSlots: Int? {
        guard !SubscriptionService.shared.subscription.isActive else { return nil }
        return max(0, Self.freeSongLimit - heldCount)
    }

    /// Whether the next new download would be refused.
    var isAtFreeLimit: Bool { remainingFreeSlots == 0 }

    /// What a container download did: how many tracks it queued, and how
    /// many it left behind because the free limit was reached.
    struct BatchResult: Equatable {
        var queued = 0
        var heldBack = 0
    }

    /// Whether the manager can download this at all: a Plex or Subsonic
    /// track carrying its stream URL.
    func canDownload(_ item: PlayableContent) -> Bool {
        [.plex, .subsonic].contains(item.content.service) && item.content.type == .track && item.previewURL != nil
    }

    func isDownloaded(_ item: PlayableContent) -> Bool {
        items[Self.key(for: item)]?.state == .completed
    }

    func isDownloading(_ item: PlayableContent) -> Bool {
        guard let entry = items[Self.key(for: item)] else { return false }
        return entry.state != .completed
    }

    func progress(for item: PlayableContent) -> Double? {
        guard let entry = items[Self.key(for: item)], entry.state != .completed else { return nil }
        return entry.progress
    }

    /// The local file for a downloaded track, or nil. Playback prefers this
    /// over the server URL, so downloaded tracks work away from the server.
    func localURL(for item: PlayableContent) -> URL? {
        guard let entry = items[Self.key(for: item)], entry.state == .completed else { return nil }
        let url = Self.fileURL(key: entry.key, fileExtension: entry.fileExtension)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Whether the manager can download this whole: a Plex or Subsonic
    /// album, playlist or artist whose tracks the local queue knows how to
    /// fetch (the same fetch feeds the download).
    func canDownload(contentsOf container: PlayableContent) -> Bool {
        [.plex, .subsonic].contains(container.content.service)
            && [.album, .playlist, .artist].contains(container.content.type)
            && LocalPlaybackService.shared.canPlayContainerLocally(container)
    }

    /// Containers with every track on the device, newest first.
    var completedContainers: [Container] {
        containers.values.filter { containerState(key: $0.key) == .downloaded }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Containers still coming down, oldest first.
    var activeContainers: [Container] {
        containers.values.filter {
            if case .downloading = containerState(key: $0.key) { return true }
            return false
        }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Where a container downloaded whole stands, or nil if it never was
    /// (or one of its songs has since been removed on its own, which
    /// forgets the container — see `pruneContainers`).
    func containerState(for container: PlayableContent) -> ContainerState? {
        containerState(key: Self.containerKey(for: container))
    }

    func containerState(key: String) -> ContainerState? {
        guard let container = containers[key], !container.trackKeys.isEmpty else { return nil }
        let entries = container.trackKeys.compactMap { items[$0] }
        guard entries.count == container.trackKeys.count else { return nil }
        if entries.allSatisfy({ $0.state == .completed }) { return .downloaded }
        let landed = entries.reduce(0.0) { $0 + ($1.state == .completed ? 1 : $1.progress) }
        return .downloading(landed / Double(entries.count))
    }

    func isDownloaded(contentsOf container: PlayableContent) -> Bool {
        containerState(for: container) == .downloaded
    }

    func isDownloading(contentsOf container: PlayableContent) -> Bool {
        if case .downloading = containerState(for: container) { return true }
        return false
    }

    /// The fraction of a container that has landed, while it's coming down.
    func progress(forContentsOf container: PlayableContent) -> Double? {
        if case let .downloading(fraction) = containerState(for: container) { return fraction }
        return nil
    }

    /// How many of a container's tracks are on the device, and how many it has.
    func trackCounts(forContainer key: String) -> (downloaded: Int, total: Int) {
        guard let container = containers[key] else { return (0, 0) }
        let downloaded = container.trackKeys.filter { items[$0]?.state == .completed }.count
        return (downloaded, container.trackKeys.count)
    }

    // MARK: - Downloading

    /// Queues a track as a batch of one — the system card still shows it
    /// and lets it be cancelled. Already-downloaded and in-flight tracks
    /// are left alone. Returns false when the free limit stops a new track;
    /// a paused or failed one already holds its slot and always resumes.
    @discardableResult
    func download(_ item: PlayableContent) -> Bool {
        guard canDownload(item), !isDownloaded(item) else { return false }
        if takesNewSlot(item), isAtFreeLimit { return false }
        queue(item)
        ContinuedDownloadTask.shared.track(downloadKeys: [Self.key(for: item)], title: "Downloading \(item.title)")
        return true
    }

    /// Queues everything inside an album, playlist or artist, fetched the
    /// way the local queue fetches it — every page, so a long playlist
    /// comes whole — as one batch the system shows and keeps running.
    /// Without Super the batch fills the free slots that are left, in the
    /// container's order, and reports what it couldn't take. When every
    /// track is here or on its way, the container is remembered with its
    /// tracks, so it can be badged and removed as one; a batch the limit
    /// cut short isn't, since it doesn't stand for the whole set.
    @discardableResult
    func download(contentsOf container: PlayableContent) async -> BatchResult {
        guard canDownload(contentsOf: container) else { return BatchResult() }
        var tracks: [PlayableContent] = []
        var offset = 0
        // Bounded: a source that quietly ignored `offset` would otherwise
        // hand back its first page forever.
        for _ in 0 ..< 200 {
            let page = await LocalPlaybackService.shared.containerTracks(for: container, offset: offset)
            guard !page.isEmpty else { break }
            tracks.append(contentsOf: page)
            offset += page.count
        }
        let downloadable = tracks.filter { canDownload($0) }
        guard !downloadable.isEmpty else { return BatchResult() }

        var result = BatchResult()
        var keys: [String] = []
        for track in downloadable where !isDownloaded(track) {
            if takesNewSlot(track), isAtFreeLimit {
                result.heldBack += 1
                continue
            }
            queue(track)
            keys.append(Self.key(for: track))
            result.queued += 1
        }
        if result.heldBack == 0 {
            let key = Self.containerKey(for: container)
            containers[key] = Container(
                key: key,
                service: container.content.service,
                contentID: container.content.id,
                type: container.content.type,
                title: container.title,
                subtitle: container.metadata?.artist ?? container.subtitle,
                artwork: container.thumbnail ?? container.artwork,
                createdAt: containers[key]?.createdAt ?? .now,
                trackKeys: downloadable.map { Self.key(for: $0) }
            )
        }
        scheduleSave()
        if !keys.isEmpty {
            ContinuedDownloadTask.shared.track(downloadKeys: keys, title: "Downloading \(container.title)")
        }
        return result
    }

    /// Whether downloading this would add an entry, as opposed to resuming
    /// one that already counts against the limit.
    private func takesNewSlot(_ item: PlayableContent) -> Bool {
        items[Self.key(for: item)] == nil
    }

    /// Removes every track of a container downloaded whole — cancelling
    /// what's still coming — and forgets the container.
    func removeDownload(contentsOf container: PlayableContent) {
        removeContainer(key: Self.containerKey(for: container))
    }

    func removeContainer(key: String) {
        guard let container = containers[key] else { return }
        containers[key] = nil
        for trackKey in container.trackKeys {
            remove(key: trackKey)
        }
        scheduleSave()
    }

    /// Forgets a container once any of its tracks is gone — removed on its
    /// own from a row or the Downloads list, cancelled, or missing from
    /// disk. A container stands for the whole set; with a track out, it's
    /// back to being songs, and can be downloaded whole again.
    private func pruneContainers() {
        for container in containers.values where container.trackKeys.contains(where: { items[$0] == nil }) {
            containers[container.key] = nil
        }
    }

    /// `download(_:)` without the batch bookkeeping, for callers that batch
    /// themselves.
    private func queue(_ item: PlayableContent) {
        // The stream as the transcoding setting delivers it to this device —
        // a download made under "MP3, 128 kbps" is that, and saved as .mp3.
        guard canDownload(item), let url = item.playbackStreamURL else { return }
        let key = Self.key(for: item)
        if let existing = items[key] {
            if existing.state == .completed || existing.isActive { return }
            resume(key: key)
            return
        }
        let entry = Item(
            key: key,
            service: item.content.service,
            contentID: item.content.id,
            title: item.title,
            subtitle: item.metadata?.artist ?? item.subtitle,
            artwork: item.thumbnail ?? item.artwork,
            url: url,
            fileExtension: Self.fileExtension(for: item, url: url),
            createdAt: .now,
            state: .queued,
            sourceURL: item.previewURL,
            audioCodec: item.metadata?.audioCodec
        )
        items[key] = entry
        start(entry)
        scheduleSave()
    }

    func pause(key: String) {
        guard var entry = items[key], entry.isActive else { return }
        entry.state = .paused
        items[key] = entry
        session.getAllTasks { tasks in
            for task in tasks where DownloadNaming.parseTaskDescription(task.taskDescription)?.key == key {
                if let download = task as? URLSessionDownloadTask {
                    download.cancel { [weak self] data in
                        Task { @MainActor in self?.store(resumeData: data, for: key) }
                    }
                } else {
                    task.cancel()
                }
            }
        }
        scheduleSave()
    }

    func resume(key: String) {
        guard var entry = items[key], entry.state == .paused || entry.state == .failed else { return }
        entry.state = .queued
        entry.error = nil
        entry.applyStreamingQuality()
        items[key] = entry
        start(entry)
        scheduleSave()
        ContinuedDownloadTask.shared.track(downloadKeys: [key], title: "Downloading \(entry.title)")
    }

    /// Stops and forgets a download that hasn't finished.
    func cancel(key: String) {
        guard let entry = items[key], entry.state != .completed else { return }
        items[key] = nil
        lastProgressPublish[key] = nil
        session.getAllTasks { tasks in
            for task in tasks where DownloadNaming.parseTaskDescription(task.taskDescription)?.key == key {
                task.cancel()
            }
        }
        try? FileManager.default.removeItem(at: Self.fileURL(key: entry.key, fileExtension: entry.fileExtension))
        pruneContainers()
        scheduleSave()
    }

    func removeDownload(_ item: PlayableContent) {
        remove(key: Self.key(for: item))
    }

    /// Deletes a finished download's file and its entry.
    func remove(key: String) {
        guard let entry = items[key] else { return }
        if entry.state != .completed {
            cancel(key: key)
            return
        }
        try? FileManager.default.removeItem(at: Self.fileURL(key: entry.key, fileExtension: entry.fileExtension))
        items[key] = nil
        pruneContainers()
        scheduleSave()
    }

    func removeAllCompleted() {
        for entry in completed {
            try? FileManager.default.removeItem(at: Self.fileURL(key: entry.key, fileExtension: entry.fileExtension))
            items[entry.key] = nil
        }
        pruneContainers()
        scheduleSave()
    }

    func pauseAll() {
        for entry in active where entry.isActive {
            pause(key: entry.key)
        }
    }

    func resumeAll() {
        for entry in active where entry.state == .paused || entry.state == .failed {
            resume(key: entry.key)
        }
    }

    private func start(_ entry: Item) {
        var request = URLRequest(url: entry.url)
        request.allowsCellularAccess = allowsCellular
        request.allowsExpensiveNetworkAccess = allowsCellular
        request.allowsConstrainedNetworkAccess = allowsCellular

        let task: URLSessionDownloadTask
        if let resumeData = entry.resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            task = session.downloadTask(with: request)
        }
        // Key and extension travel with the task, so the relay can put the
        // file in place the moment it lands — before the system deletes the
        // temporary copy — even after a relaunch with no manifest in memory.
        task.taskDescription = DownloadNaming.taskDescription(key: entry.key, fileExtension: entry.fileExtension)
        task.priority = URLSessionTask.highPriority
        task.resume()

        var updated = entry
        updated.state = .downloading
        updated.resumeData = nil
        items[entry.key] = updated
    }

    // MARK: - Relay callbacks

    fileprivate func didWrite(key: String, received: Int64, expected: Int64) {
        guard var entry = items[key], entry.state != .completed else { return }
        // Bytes arrive many times a second; publish a few times a second.
        let now = Date.now
        let last = lastProgressPublish[key] ?? .distantPast
        guard now.timeIntervalSince(last) > 0.2 || received == expected else { return }
        lastProgressPublish[key] = now
        entry.state = .downloading
        entry.bytesReceived = received
        entry.bytesExpected = expected
        items[key] = entry
    }

    fileprivate func didFinish(key: String, fileSize: Int64?) {
        guard var entry = items[key] else { return }
        entry.state = .completed
        entry.bytesReceived = entry.bytesExpected
        entry.fileSize = fileSize
        entry.resumeData = nil
        entry.error = nil
        items[key] = entry
        lastProgressPublish[key] = nil
        scheduleSave()
    }

    fileprivate func didFail(key: String, error: Error, resumeData: Data?) {
        guard var entry = items[key], entry.state != .completed else { return }
        let nsError = error as NSError
        let cancelled = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
        entry.resumeData = resumeData ?? entry.resumeData
        entry.state = cancelled ? .paused : .failed
        entry.error = cancelled ? nil : error.localizedDescription
        items[key] = entry
        scheduleSave()
    }

    fileprivate func store(resumeData: Data?, for key: String) {
        guard var entry = items[key], let resumeData else { return }
        entry.resumeData = resumeData
        items[key] = entry
        scheduleSave()
    }

    fileprivate func didFinishBackgroundEvents() {
        let handler = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        handler?()
    }

    // MARK: - Startup

    /// Marks whatever the session is still carrying as downloading, and
    /// re-queues anything the manifest thinks is in flight but the session
    /// no longer has (the system dropped it, or the app was force-quit
    /// before the task was made).
    private func reattachSessionTasks() {
        session.getAllTasks { [weak self] tasks in
            let carried = Set(tasks.compactMap { DownloadNaming.parseTaskDescription($0.taskDescription)?.key })
            Task { @MainActor in
                guard let self else { return }
                for entry in self.items.values where entry.state != .completed && entry.state != .paused {
                    if carried.contains(entry.key) {
                        var updated = entry
                        updated.state = .downloading
                        self.items[entry.key] = updated
                    } else if entry.state == .downloading || entry.state == .queued {
                        self.start(entry)
                    }
                }
                self.scheduleSave()
            }
        }
    }

    /// A completed entry whose file has gone is no download at all; a file
    /// with no entry (finished while the manifest was unsaved) becomes one.
    private func reconcileWithDisk() {
        for entry in items.values where entry.state == .completed {
            let url = Self.fileURL(key: entry.key, fileExtension: entry.fileExtension)
            if !FileManager.default.fileExists(atPath: url.path) {
                items[entry.key] = nil
            }
        }
        for entry in items.values where entry.state != .completed {
            let url = Self.fileURL(key: entry.key, fileExtension: entry.fileExtension)
            if let size = Self.size(of: url) {
                var updated = entry
                updated.state = .completed
                updated.fileSize = size
                updated.resumeData = nil
                items[entry.key] = updated
            }
        }
    }

    /// The first build kept Plex downloads in its own folder with no
    /// manifest; they move over as completed downloads so nothing is lost.
    private func adoptLegacyPlexDownloads() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let legacy = support?.appendingPathComponent("PlexDownloads", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil),
              !files.isEmpty else { return }
        for file in files {
            let key = file.deletingPathExtension().lastPathComponent
            let ext = file.pathExtension
            let destination = Self.fileURL(key: key, fileExtension: ext)
            guard (try? FileManager.default.moveItem(at: file, to: destination)) != nil else { continue }
            if items[key] == nil {
                items[key] = Item(
                    key: key,
                    service: .plex,
                    contentID: key,
                    title: "Downloaded Track",
                    subtitle: "Plex",
                    artwork: nil,
                    url: destination,
                    fileExtension: ext,
                    createdAt: .now,
                    state: .completed,
                    fileSize: Self.size(of: destination)
                )
            }
        }
        try? FileManager.default.removeItem(at: legacy)
        scheduleSave()
    }

    // MARK: - Storage

    /// Filesystem-safe key for a track — see `DownloadNaming`.
    static func key(for item: PlayableContent) -> String {
        DownloadNaming.key(for: item)
    }

    /// Key for a container downloaded whole: its type in front of the same
    /// safe id its tracks use, so an album and a playlist that happen to
    /// share an id on the server stay apart.
    static func containerKey(for container: PlayableContent) -> String {
        "\(container.content.type.id.lowercased())-\(key(for: container))"
    }

    private static func fileExtension(for item: PlayableContent, url: URL) -> String {
        DownloadNaming.fileExtension(for: item, url: url)
    }

    nonisolated static var directory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Downloads", isDirectory: true)
    }

    nonisolated static func fileURL(key: String, fileExtension: String) -> URL {
        directory.appendingPathComponent(key).appendingPathExtension(fileExtension)
    }

    nonisolated private static var manifestURL: URL {
        directory.appendingPathComponent("manifest.json")
    }

    nonisolated private static var containerManifestURL: URL {
        directory.appendingPathComponent("containers.json")
    }

    /// Creates the folder, protected until first unlock and left out of
    /// backups: the files are the user's own server's, fetched again on
    /// demand.
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

    nonisolated static func size(of url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    private static func loadManifest() -> [String: Item] {
        guard let data = try? Data(contentsOf: manifestURL),
              let items = try? JSONDecoder().decode([Item].self, from: data) else { return [:] }
        return Dictionary(items.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func loadContainerManifest() -> [String: Container] {
        guard let data = try? Data(contentsOf: containerManifestURL),
              let containers = try? JSONDecoder().decode([Container].self, from: data) else { return [:] }
        return Dictionary(containers.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Coalesces saves: progress alone never writes, and bursts of state
    /// changes (an album finishing) write once.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            let snapshot = Array(self.items.values)
            let containerSnapshot = Array(self.containers.values)
            await Task.detached(priority: .utility) {
                if let data = try? JSONEncoder().encode(snapshot) {
                    try? data.write(to: Self.manifestURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
                if let data = try? JSONEncoder().encode(containerSnapshot) {
                    try? data.write(to: Self.containerManifestURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
            }.value
        }
    }
}

/// The session's delegate. Lives off the main actor because the session
/// calls it on its own queue — and, crucially, has to move a finished file
/// out of the temporary location before returning, which can't wait for a
/// hop to the main actor.
private final class DownloadSessionRelay: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var manager: DownloadManager?

    private func key(of task: URLSessionTask) -> (key: String, fileExtension: String)? {
        DownloadNaming.parseTaskDescription(task.taskDescription)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let (key, _) = key(of: downloadTask) else { return }
        Task { @MainActor in
            self.manager?.didWrite(key: key, received: totalBytesWritten, expected: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (key, fileExtension) = key(of: downloadTask) else { return }
        // A refused request (Plex answering a transcode it can't do with a
        // 400 page) still lands here as a finished file. Fail it instead of
        // keeping the page as a song; nothing to resume from.
        if let refused = StreamResponseCheck.refusal(in: downloadTask.response) {
            Task { @MainActor in
                self.manager?.didFail(key: key, error: refused, resumeData: nil)
            }
            return
        }
        let destination = DownloadManager.fileURL(key: key, fileExtension: fileExtension)
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destination.path
            )
        } catch {
            Task { @MainActor in
                self.manager?.didFail(key: key, error: error, resumeData: nil)
            }
            return
        }
        let size = DownloadManager.size(of: destination)
        Task { @MainActor in
            self.manager?.didFinish(key: key, fileSize: size)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let (key, _) = key(of: task) else { return }
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Task { @MainActor in
            self.manager?.didFail(key: key, error: error, resumeData: resumeData)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.manager?.didFinishBackgroundEvents()
        }
    }
}
