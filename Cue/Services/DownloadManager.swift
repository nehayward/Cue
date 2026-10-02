import Defaults
import Foundation
import MusicSearchKit
import Network
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
///
/// Cellular: a download that may not use the network it's on waits for
/// one it may (`.waiting`), with its task left on the session, so the
/// system starts it the moment Wi‑Fi is back even with Cue suspended. The
/// person is asked once whether to let it use cellular now instead
/// (`CellularDownloadPrompt`). Failures the network caused retry on their
/// own when a usable network comes back.
@MainActor
@Observable
final class DownloadManager {
    static let shared = DownloadManager()

    struct Item: Codable, Identifiable, Hashable, Sendable {
        enum State: String, Codable, Sendable {
            /// `waiting`: on the session, but held until a network it may
            /// use — Wi‑Fi, when cellular is off for it — or any network.
            case queued, downloading, waiting, paused, completed, failed
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
        /// The person let this one use cellular though the setting is off.
        var cellularOverride: Bool?
        /// Whether the request its session task was made with may use
        /// cellular. Resume data carries that request, so when the answer
        /// changes the transfer starts over rather than resume under the
        /// old rule.
        var requestAllowsCellular: Bool?
        /// It failed for want of a network (dropped, timed out, the server
        /// out of reach), so it retries by itself when one comes back.
        var failedOnNetwork: Bool?

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
        /// The track as it was when queued — its album, artist and stream
        /// URL — so the downloads library can group what's here by album
        /// and artist and play it. Nil for downloads made before this was
        /// kept; those are rebuilt from the title and subtitle.
        var track: PlayableContent?

        var id: String { key }

        var progress: Double {
            DownloadNaming.progress(received: bytesReceived, expected: bytesExpected)
        }

        /// Coming down, or on its way to: queued, running, or waiting for a
        /// network it may use.
        var isActive: Bool {
            state == .queued || state == .downloading || state == .waiting
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

    /// Whether transfers may use cellular data. Turning it on starts what
    /// was waiting for Wi‑Fi; turning it off moves what's on cellular right
    /// now to wait for Wi‑Fi.
    var allowsCellular: Bool {
        didSet {
            UserDefaults.standard.set(allowsCellular, forKey: AppStorageKeys.downloadsOverCellular)
            guard allowsCellular != oldValue else { return }
            applyCellularSetting()
        }
    }

    /// The network as downloads see it.
    enum Connectivity: Equatable {
        /// No path at all.
        case none
        /// Cellular, a personal hotspot, or Low Data Mode.
        case metered
        /// Wi‑Fi or wired, not constrained.
        case unmetered
    }

    /// What the path monitor last reported. Until its first report (which
    /// comes as soon as it starts) downloads are assumed free to run.
    private(set) var network: Connectivity = .unmetered

    /// The completion handler iOS gives the app when it relaunches it for
    /// this session's events; called once the delegate has drained them.
    @ObservationIgnored var backgroundCompletionHandler: (() -> Void)?

    @ObservationIgnored private let relay = DownloadSessionRelay()
    @ObservationIgnored private var lastProgressPublish: [String: Date] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var hasNetworkReport = false
    /// The session task each download runs on now. Events from any other
    /// task for the same key — one replaced by a restart, whose
    /// cancellation arrives late — are stale and ignored.
    @ObservationIgnored private var taskIDs: [String: Int] = [:]
    /// Downloads held back by the cellular setting that the prompt will
    /// offer to start; gathered so a batch asks once.
    @ObservationIgnored private var cellularPromptKeys: [String] = []
    @ObservationIgnored private var cellularPromptTask: Task<Void, Never>?

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
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let network: Connectivity = path.status != .satisfied
                ? .none
                : (path.isExpensive || path.isConstrained) ? .metered : .unmetered
            Task { @MainActor in self?.networkDidChange(to: network) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "dance.cue.downloads.path", qos: .utility))
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

    /// Queued or coming down now. A paused or failed download isn't: it
    /// won't move again until it's resumed (see `stoppedDownload(for:)`).
    func isDownloading(_ item: PlayableContent) -> Bool {
        items[Self.key(for: item)]?.isActive == true
    }

    /// The entry for a download that paused or failed part-way, so a menu
    /// can offer to resume or retry it rather than claim it's still running.
    func stoppedDownload(for item: PlayableContent) -> Item? {
        guard let entry = items[Self.key(for: item)], entry.state == .paused || entry.state == .failed else { return nil }
        return entry
    }

    /// Downloads that paused or failed and wait on the person to resume them.
    var stoppedCount: Int {
        items.values.filter { $0.state == .paused || $0.state == .failed }.count
    }

    /// The entry for a download waiting for a network it may use.
    func waitingDownload(for item: PlayableContent) -> Item? {
        guard let entry = items[Self.key(for: item)], entry.state == .waiting else { return nil }
        return entry
    }

    /// Downloads waiting for Wi‑Fi that cellular could start now, were it
    /// allowed for them.
    var cellularHeldKeys: [String] {
        guard network == .metered else { return [] }
        return active.filter { $0.state == .waiting && !mayUseCellular($0) }.map(\.key)
    }

    /// The keys of a container's tracks that wait for a network.
    func waitingTrackKeys(forContentsOf container: PlayableContent) -> [String] {
        guard let entry = containers[Self.containerKey(for: container)] else { return [] }
        return entry.trackKeys.filter { items[$0]?.state == .waiting }
    }

    func progress(for item: PlayableContent) -> Double? {
        guard let entry = items[Self.key(for: item)], entry.isActive else { return nil }
        return entry.progress
    }

    /// The local file for a downloaded track, or nil. Playback prefers this
    /// over the server URL, so downloaded tracks work away from the server.
    func localURL(for item: PlayableContent) -> URL? {
        guard var entry = items[Self.key(for: item)], entry.state == .completed else { return nil }
        let fixed = Self.containerFixed(key: entry.key, fileExtension: entry.fileExtension, in: Self.fileURL)
        if fixed != entry.fileExtension {
            entry.fileExtension = fixed
            items[entry.key] = entry
            scheduleSave()
        }
        let url = Self.fileURL(key: entry.key, fileExtension: entry.fileExtension)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// A copy an earlier build saved under its codec's name (`.alac`), which
    /// the player can't open, renamed to its container's (`.m4a`). Returns
    /// the extension to use from now on: the new one once the file has
    /// moved, the old one if it couldn't.
    static func containerFixed(key: String, fileExtension: String, in fileURL: (String, String) -> URL) -> String {
        let fixed = StreamTranscoding.fileExtension(forCodec: fileExtension)
        guard fixed != fileExtension else { return fileExtension }
        let from = fileURL(key, fileExtension)
        let to = fileURL(key, fixed)
        let files = FileManager.default
        if files.fileExists(atPath: to.path) { return fixed }
        guard files.fileExists(atPath: from.path), (try? files.moveItem(at: from, to: to)) != nil else { return fileExtension }
        return fixed
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

    /// How many of a container's tracks paused or failed, and so won't
    /// finish without being resumed.
    func stoppedTrackCount(forContainer key: String) -> Int {
        guard let container = containers[key] else { return 0 }
        return container.trackKeys.filter { items[$0]?.state == .paused || items[$0]?.state == .failed }.count
    }

    func stoppedTrackCount(forContentsOf container: PlayableContent) -> Int {
        stoppedTrackCount(forContainer: Self.containerKey(for: container))
    }

    /// Resumes or retries every track of a container that paused or failed.
    func resumeDownload(contentsOf container: PlayableContent) {
        guard let entry = containers[Self.containerKey(for: container)] else { return }
        let keys = entry.trackKeys.filter { items[$0]?.state == .paused || items[$0]?.state == .failed }
        resume(keys: keys, title: container.title)
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
        didQueue([Self.key(for: item)], title: item.title)
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
        let tracks = await LocalPlaybackService.shared.allContainerTracks(for: container)
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
        didQueue(keys, title: container.title)
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
            audioCodec: item.metadata?.audioCodec,
            track: item
        )
        items[key] = entry
        start(entry)
        scheduleSave()
    }

    func pause(key: String) {
        guard var entry = items[key], entry.isActive else { return }
        entry.state = .paused
        items[key] = entry
        taskIDs[key] = nil
        settleSessionTasks(for: key)
        scheduleSave()
    }

    /// Resumes or retries a download the person stopped, or that failed.
    func resume(key: String) {
        resume(keys: [key], title: items[key]?.title ?? "")
    }

    private func resume(keys: [String], title: String) {
        var resumed: [String] = []
        for key in keys {
            guard var entry = items[key], entry.state == .paused || entry.state == .failed else { continue }
            entry.state = .queued
            entry.error = nil
            entry.failedOnNetwork = nil
            entry.applyStreamingQuality()
            items[key] = entry
            start(entry)
            resumed.append(key)
        }
        scheduleSave()
        didQueue(resumed, title: title)
    }

    /// Lets these downloads use cellular though the setting is off — the
    /// person's answer to the prompt, for these songs only. A task made
    /// without cellular is replaced; its resume data belongs to that
    /// request.
    func allowCellular(forKeys keys: [String]) {
        var started: [String] = []
        for key in keys {
            guard var entry = items[key], entry.state != .completed else { continue }
            entry.cellularOverride = true
            if entry.state == .paused || entry.state == .failed {
                entry.state = .queued
                entry.error = nil
                entry.failedOnNetwork = nil
                entry.applyStreamingQuality()
            }
            items[key] = entry
            if entry.requestAllowsCellular != true || entry.state == .queued {
                start(entry)
            } else {
                refreshWaiting(key: key)
            }
            started.append(key)
        }
        scheduleSave()
        track(started)
    }

    /// Stops and forgets a download that hasn't finished.
    func cancel(key: String) {
        guard let entry = items[key], entry.state != .completed else { return }
        items[key] = nil
        lastProgressPublish[key] = nil
        taskIDs[key] = nil
        settleSessionTasks(for: key)
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
        let keys = active.filter { $0.state == .paused || $0.state == .failed }.map(\.key)
        resume(keys: keys, title: keys.count == 1 ? items[keys[0]]?.title ?? "" : "")
    }

    /// Makes the session task for a download and puts it on its way — or,
    /// when the network it's on is one it may not use, leaves the task with
    /// the session to wait for one (the system starts it by itself, even
    /// with the app suspended) and marks it waiting. Any older task for the
    /// same key is cancelled once this one is in place.
    private func start(_ entry: Item) {
        var entry = entry
        let cellular = allowsCellular || entry.cellularOverride == true
        if entry.resumeData != nil, let made = entry.requestAllowsCellular, made != cellular {
            entry.resumeData = nil
            entry.bytesReceived = 0
        }

        var request = URLRequest(url: entry.url)
        request.allowsCellularAccess = cellular
        request.allowsExpensiveNetworkAccess = cellular
        request.allowsConstrainedNetworkAccess = cellular

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
        taskIDs[entry.key] = task.taskIdentifier
        task.resume()

        entry.requestAllowsCellular = cellular
        entry.resumeData = nil
        entry.state = mayUse(entry) ? .downloading : .waiting
        items[entry.key] = entry
        settleSessionTasks(for: entry.key)
    }

    /// Cancels the session's tasks for a key that aren't the one the
    /// download runs on now — all of them for a download that's paused or
    /// gone. A paused one keeps its resume data. Reads the manager when the
    /// session answers, not when asked, so a resume tapped in between
    /// keeps its fresh task.
    private func settleSessionTasks(for key: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let tasks = await self.session.allTasks
            let entry = self.items[key]
            let current = entry?.isActive == true ? self.taskIDs[key] : nil
            for task in tasks where DownloadNaming.parseTaskDescription(task.taskDescription)?.key == key {
                guard task.taskIdentifier != current, task.state != .completed else { continue }
                if entry?.state == .paused, let download = task as? URLSessionDownloadTask {
                    download.cancel { [weak self] data in
                        Task { @MainActor in self?.store(resumeData: data, for: key) }
                    }
                } else {
                    task.cancel()
                }
            }
        }
    }

    // MARK: - Network

    /// Whether this download's request may use cellular.
    private func mayUseCellular(_ entry: Item) -> Bool {
        entry.requestAllowsCellular ?? (allowsCellular || entry.cellularOverride == true)
    }

    /// Whether this download can move on the network there is now.
    private func mayUse(_ entry: Item) -> Bool {
        switch network {
        case .none: false
        case .metered: mayUseCellular(entry)
        case .unmetered: true
        }
    }

    /// Puts a waiting download back to running once it may use the
    /// network, or an active one to waiting when it may not.
    private func refreshWaiting(key: String) {
        guard var entry = items[key], entry.isActive, entry.state != .queued else { return }
        let state: Item.State = mayUse(entry) ? .downloading : .waiting
        guard entry.state != state else { return }
        entry.state = state
        items[key] = entry
    }

    private func networkDidChange(to network: Connectivity) {
        let first = !hasNetworkReport
        hasNetworkReport = true
        guard first || network != self.network else { return }
        let before = self.network
        self.network = network

        // On cellular, every transfer runs under the rule in force: one
        // made before the setting (or the person) changed its mind is
        // replaced. What was waiting and may run now, and what was running
        // and may not, swap.
        var resumed = network == .metered ? conformToCellularSetting() : []
        for entry in items.values where entry.state == .downloading || entry.state == .waiting {
            let wasWaiting = entry.state == .waiting
            refreshWaiting(key: entry.key)
            if wasWaiting, items[entry.key]?.state == .downloading {
                resumed.append(entry.key)
            }
        }

        // A usable network is back: retry what the network made fail, and
        // make sure what's running has a task — the session may have
        // dropped one while the app wasn't looking.
        if network != .none, first || before == .none || network == .unmetered {
            for entry in items.values where entry.state == .failed && entry.failedOnNetwork == true {
                var retry = entry
                retry.state = .queued
                retry.error = nil
                retry.failedOnNetwork = nil
                retry.applyStreamingQuality()
                items[entry.key] = retry
                start(retry)
                if items[entry.key]?.state == .downloading {
                    resumed.append(entry.key)
                }
            }
        }
        if !first, !resumed.isEmpty {
            ensureSessionTasks(for: resumed)
        }
        scheduleSave()
        // Unless this is the launch report, when nothing the person did is
        // running yet and the reattach already accounts for it.
        if !first {
            track(resumed)
        }
    }

    /// Restarts any of these the session isn't carrying.
    private func ensureSessionTasks(for keys: [String]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let tasks = await self.session.allTasks
            let carried = Set(tasks.filter { $0.state != .completed }.compactMap { DownloadNaming.parseTaskDescription($0.taskDescription)?.key })
            for key in keys where !carried.contains(key) {
                guard let entry = self.items[key], entry.isActive else { continue }
                self.start(entry)
            }
        }
    }

    /// The setting changed. Only cellular is affected: on Wi‑Fi running
    /// transfers are left to finish, and brought under the rule if the
    /// phone moves to cellular before they do.
    private func applyCellularSetting() {
        guard network == .metered else { return }
        let started = conformToCellularSetting()
        scheduleSave()
        track(started)
    }

    /// Replaces the task of any active download whose request disagrees
    /// with what it may do now — cellular turned on (or allowed for it)
    /// since it was made, or turned off — and returns the ones now running.
    /// Their transfer starts over; on cellular with no permission to use
    /// it, there was nothing moving to keep.
    private func conformToCellularSetting() -> [String] {
        var started: [String] = []
        for entry in items.values where entry.isActive {
            let allowed = allowsCellular || entry.cellularOverride == true
            guard entry.requestAllowsCellular != allowed else { continue }
            start(entry)
            if items[entry.key]?.state == .downloading { started.append(entry.key) }
        }
        return started
    }

    // MARK: - Batches

    /// After the person queues or resumes downloads: the ones under way go
    /// on the system's card, and any held back only because cellular is
    /// off get one question.
    private func didQueue(_ keys: [String], title: String) {
        track(keys, title: title)
        let held = keys.filter { key in
            guard network == .metered, let entry = items[key] else { return false }
            return entry.state == .waiting && !mayUseCellular(entry)
        }
        guard !held.isEmpty else { return }
        cellularPromptKeys.append(contentsOf: held.filter { !cellularPromptKeys.contains($0) })
        // After a beat: the tap usually comes from a menu that's still
        // closing, and a presentation started under it is dropped. Also
        // gathers a burst (Resume All) into one question.
        cellularPromptTask?.cancel()
        cellularPromptTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.presentCellularPrompt()
        }
    }

    /// Asks about downloads held for Wi‑Fi, from a row or menu that offers it.
    func offerCellular(forKeys keys: [String]) {
        didQueue(keys, title: "")
    }

    private func presentCellularPrompt() {
        let keys = cellularPromptKeys.filter { key in
            guard let entry = items[key] else { return false }
            return entry.state == .waiting && !mayUseCellular(entry)
        }
        cellularPromptKeys = []
        guard !keys.isEmpty, network == .metered else { return }
        let titles = keys.compactMap { items[$0]?.title }
        CellularDownloadPrompt.present(titles: titles) { [weak self] answer in
            guard let self else { return }
            switch answer {
            case .thisTime:
                self.allowCellular(forKeys: keys)
            case .always:
                self.allowsCellular = true
            case .wait:
                break
            }
        }
    }

    /// Puts the downloads that are running on the system's card.
    private func track(_ keys: [String], title: String = "") {
        let running = keys.filter { items[$0]?.state == .downloading || items[$0]?.state == .queued }
        guard !running.isEmpty else { return }
        let name: String
        if !title.isEmpty {
            name = title
        } else if running.count == 1, let only = items[running[0]]?.title {
            name = only
        } else {
            name = "\(running.count) songs"
        }
        ContinuedDownloadTask.shared.track(downloadKeys: running, title: "Downloading \(name)")
    }

    // MARK: - Relay callbacks

    /// Whether an event from this task is about the download as it is now.
    private func isCurrent(task identifier: Int, key: String) -> Bool {
        guard let current = taskIDs[key] else { return true }
        return current == identifier
    }

    fileprivate func didWrite(key: String, task identifier: Int, received: Int64, expected: Int64) {
        guard isCurrent(task: identifier, key: key),
              var entry = items[key], entry.isActive else { return }
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

    /// A file landed. Taken from whichever task brought it — it's the song
    /// either way — and any other task for the key is let go.
    fileprivate func didFinish(key: String, fileSize: Int64?) {
        guard var entry = items[key] else { return }
        taskIDs[key] = nil
        entry.state = .completed
        entry.bytesReceived = entry.bytesExpected
        entry.fileSize = fileSize
        entry.resumeData = nil
        entry.error = nil
        items[key] = entry
        lastProgressPublish[key] = nil
        settleSessionTasks(for: key)
        scheduleSave()
    }

    fileprivate func didFail(key: String, task identifier: Int, error: Error, resumeData: Data?) {
        guard isCurrent(task: identifier, key: key),
              var entry = items[key], entry.state != .completed else { return }
        taskIDs[key] = nil
        let nsError = error as NSError
        let cancelled = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
        entry.resumeData = resumeData ?? entry.resumeData
        entry.state = cancelled ? .paused : .failed
        entry.error = cancelled ? nil : error.localizedDescription
        entry.failedOnNetwork = cancelled ? nil : Self.isNetworkFailure(nsError)
        items[key] = entry
        scheduleSave()
    }

    /// Failures a better network would fix, as opposed to the server
    /// refusing the file.
    private static func isNetworkFailure(_ error: NSError) -> Bool {
        guard error.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorDataNotAllowed,
            NSURLErrorCallIsActive,
            NSURLErrorCannotLoadFromNetwork,
            NSURLErrorBackgroundSessionWasDisconnected,
            NSURLErrorSecureConnectionFailed,
        ].contains(error.code)
    }

    /// Keeps the resume data a pause produced — unless the download has
    /// moved on since (resumed on a fresh task), when it's stale.
    fileprivate func store(resumeData: Data?, for key: String) {
        guard var entry = items[key], entry.state == .paused || entry.state == .failed, let resumeData else { return }
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
    ///
    /// A carried task is adopted as the download's current one (the newest,
    /// if there are several), and marked running or waiting by the network;
    /// tasks for a download that's paused, failed or gone are let go.
    private func reattachSessionTasks() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let tasks = await self.session.allTasks.filter { $0.state != .completed }
            var carried: [String: Int] = [:]
            for task in tasks {
                guard let key = DownloadNaming.parseTaskDescription(task.taskDescription)?.key else { continue }
                carried[key] = max(carried[key] ?? task.taskIdentifier, task.taskIdentifier)
            }
            for entry in self.items.values where entry.state != .completed {
                if entry.isActive {
                    if let identifier = carried[entry.key], self.taskIDs[entry.key] == nil {
                        self.taskIDs[entry.key] = identifier
                        var updated = entry
                        updated.state = self.mayUse(entry) ? .downloading : .waiting
                        self.items[entry.key] = updated
                        self.settleSessionTasks(for: entry.key)
                    } else if carried[entry.key] == nil {
                        self.start(entry)
                    }
                } else if carried[entry.key] != nil {
                    self.settleSessionTasks(for: entry.key)
                }
            }
            for key in carried.keys where self.items[key] == nil {
                self.settleSessionTasks(for: key)
            }
            self.scheduleSave()
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
        let identifier = downloadTask.taskIdentifier
        Task { @MainActor in
            self.manager?.didWrite(key: key, task: identifier, received: totalBytesWritten, expected: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (key, fileExtension) = key(of: downloadTask) else { return }
        let identifier = downloadTask.taskIdentifier
        // A refused request (Plex answering a transcode it can't do with a
        // 400 page) still lands here as a finished file. Fail it instead of
        // keeping the page as a song; nothing to resume from.
        if let refused = StreamResponseCheck.refusal(in: downloadTask.response) {
            Task { @MainActor in
                self.manager?.didFail(key: key, task: identifier, error: refused, resumeData: nil)
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
                self.manager?.didFail(key: key, task: identifier, error: error, resumeData: nil)
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
        let identifier = task.taskIdentifier
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Task { @MainActor in
            self.manager?.didFail(key: key, task: identifier, error: error, resumeData: resumeData)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.manager?.didFinishBackgroundEvents()
        }
    }
}

/// The question put when a download the person just asked for can't start
/// because it's on cellular and cellular is off for downloads: let this one
/// through, always allow cellular, or wait for Wi‑Fi (it's queued either
/// way). A UIKit alert on whatever is on top, since the tap that starts a
/// download can come from a menu in any screen, sheet or the player.
@MainActor
enum CellularDownloadPrompt {
    enum Answer {
        case thisTime, always, wait
    }

    static func present(titles: [String], answer: @escaping @MainActor (Answer) -> Void) {
        guard let presenter = topViewController() else {
            answer(.wait)
            return
        }
        let heading = titles.count == 1 ? "Download Over Cellular?" : "Download \(titles.count) Songs Over Cellular?"
        let subject = titles.count == 1 ? "“\(titles[0])” is" : "\(titles.count) songs are"
        let alert = UIAlertController(
            title: heading,
            message: "Cellular downloads are off, so \(subject) waiting for Wi‑Fi. Download over cellular now instead?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: titles.count == 1 ? "Download Now" : "Download These Now", style: .default) { _ in
            answer(.thisTime)
        })
        alert.addAction(UIAlertAction(title: "Always Use Cellular", style: .default) { _ in
            answer(.always)
        })
        alert.addAction(UIAlertAction(title: "Wait for Wi‑Fi", style: .cancel) { _ in
            answer(.wait)
        })
        alert.preferredAction = alert.actions.first
        presenter.present(alert, animated: true)
    }

    /// The controller at the top of the key window's presentation chain,
    /// passing over one already on its way out.
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.filter { $0.activationState == .foregroundActive }.flatMap(\.windows)
            + scenes.flatMap(\.windows)
        let window = windows.first { $0.isKeyWindow } ?? windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
