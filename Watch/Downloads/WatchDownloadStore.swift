import Foundation
import Observation
import OSLog
import WatchKit
import WatchSync

/// Keeps the music on the watch, on the watch.
///
/// What's wanted is a list of picks — albums, playlists, artists and songs
/// by id (`WatchPicks`) — made on either device: Add Music here, Add to
/// Apple Watch on the iPhone (`PhoneConnection`). The watch looks each pick
/// up on its server itself (`WatchLibraryBrowser.songs(for:)`), downloads
/// the songs at the quality chosen here, and deletes what no pick holds any
/// more. It looks the picks up again when the sign-ins change, and every few
/// hours, so a playlist follows the server. Two ways down:
///
/// - **In the background**, on a background `URLSession`: it carries on with
///   Cue closed, and the system relaunches the app to finish up. While the
///   iPhone is connected over Bluetooth, watchOS sends the watch's traffic
///   through it — tens of KB/s, minutes a song.
/// - **Fast Download**, on an ordinary session while Cue is open, four songs
///   at a time. Its screen asks for Bluetooth to be turned off on the
///   iPhone: with no Bluetooth link the watch uses its own Wi‑Fi, at MB/s.
///   watchOS doesn't say which way a transfer went, so the speed is the
///   evidence (`RouteEstimator`), and the screen asks again while it's slow.
///   When Cue leaves the screen, what's left goes back to the background
///   session, and Fast Download picks up again on return.
///
/// Plex converts a song as it sends it, one at a time for a client, so its
/// conversions come down one at a time; a conversion that breaks off
/// (`cannot parse response`, mostly) is tried again by itself.
///
/// Files live in Application Support/Downloads as `<key>.<ext>`, with the
/// manifest beside them; the picks and their songs are kept alongside.
@MainActor
@Observable
final class WatchDownloadStore {
    static let shared = WatchDownloadStore()

    enum SessionKind: String, Codable, Sendable {
        case background, fast
    }

    struct Item: Codable, Identifiable, Sendable {
        enum State: String, Codable, Sendable {
            /// Waiting its turn, on no session yet.
            case queued
            /// On a session: coming down, or waiting for the system to
            /// start it.
            case downloading
            case completed
            /// Stopped; Fast Download, or the app coming back to the
            /// screen when the network was to blame, tries it again.
            case failed
        }

        var song: WatchSong
        /// What it's fetched at, and the suffix it's saved under.
        var quality: WatchDownloadQuality
        var fileExtension: String
        var state: State
        var bytesReceived: Int64 = 0
        var bytesExpected: Int64 = 0
        var fileSize: Int64?
        /// Where a failed transfer stopped, and the session that can pick
        /// it up — resume data doesn't cross between the two.
        var resumeData: Data?
        var resumeOn: SessionKind?
        var error: String?
        var failedOnNetwork: Bool?
        /// Times it was tried again by itself after the server broke off.
        var retries: Int?
        /// The suffix of the file an earlier download left — at another
        /// quality — kept playable while this one comes down, and deleted
        /// when it lands.
        var previousFileExtension: String?

        var id: String { song.key }
        var key: String { song.key }

        var progress: Double {
            guard bytesExpected > 0 else { return 0 }
            return min(1, max(0, Double(bytesReceived) / Double(bytesExpected)))
        }
    }

    enum FastPhase: Equatable {
        case off, running, finished
    }

    private(set) var picks: WatchPicks
    /// Each pick's songs, in play order, as last looked up.
    private(set) var songsByPick: [String: [WatchSong]]
    /// Picks being looked up now, and those the server couldn't be asked
    /// about the last time.
    private(set) var lookingUp: Set<String> = []
    private(set) var unreachable: Set<String> = []
    /// Every song on the watch or on its way, by key.
    private(set) var items: [String: Item]
    private(set) var quality: WatchDownloadQuality
    private(set) var hasChosenQuality: Bool

    // MARK: Fast Download

    private(set) var fastPhase: FastPhase = .off
    /// The speed over the last few seconds, while Fast Download runs.
    private(set) var bytesPerSecond: Double?
    private(set) var route: DownloadRoute = .measuring
    /// The fast session is waiting for a network: no Wi‑Fi in reach, and
    /// no iPhone to go through.
    private(set) var isWaitingForNetwork = false
    /// Songs this run set out to fetch, and how many have landed.
    private(set) var fastTotal = 0
    private(set) var fastCompleted = 0

    struct TaskRef {
        let kind: SessionKind
        let task: URLSessionTask
    }

    /// The session task each download runs on now. Events from any other
    /// task for the same key — one replaced, cancelled, or left on the
    /// other session — are stale and ignored.
    @ObservationIgnored private var tasks: [String: TaskRef] = [:]
    @ObservationIgnored private var lookedUpAt: Date?
    @ObservationIgnored private var resumesFastOnReturn = false
    @ObservationIgnored private var fastBytes: Int64 = 0
    @ObservationIgnored private var meter = TransferRateMeter()
    @ObservationIgnored private var estimator = RouteEstimator()
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var lastProgressPublish: [String: Date] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundCompletionHandlers: [() -> Void] = []
    @ObservationIgnored private let backgroundRelay = DownloadRelay(kind: .background)
    @ObservationIgnored private let fastRelay = DownloadRelay(kind: .fast)
    @ObservationIgnored private let logger = Logger(subsystem: "dance.cue.watch", category: "Downloads")

    @ObservationIgnored private lazy var backgroundSession: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundIdentifier)
        // Asked for by the person, so not left for the system to time.
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        return URLSession(configuration: configuration, delegate: backgroundRelay, delegateQueue: nil)
    }()

    @ObservationIgnored private lazy var fastSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = Self.fastConcurrency
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = true
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: fastRelay, delegateQueue: nil)
    }()

    nonisolated static let backgroundIdentifier = "dance.cue.watch.downloads"
    /// Songs fetched at once in Fast Download: enough to fill Wi‑Fi from a
    /// server that sends each one slowly, few enough that one finishes soon.
    static let fastConcurrency = 4
    /// Songs handed to the background session at once. The system runs
    /// them as it sees fit; each one that lands makes room for the next
    /// (the session relaunches the app for it), so an artist of hundreds
    /// doesn't sit on the session as hundreds of tasks.
    static let backgroundConcurrency = 16
    /// Times a song the server broke off is tried again before it counts
    /// as failed.
    static let retryLimit = 2
    /// How old the songs looked up for the picks get before they're looked
    /// up again, so playlists follow the server.
    static let lookUpInterval: TimeInterval = 6 * 60 * 60

    private static let qualityKey = "downloadQuality"

    private init() {
        Self.prepareDirectory()
        let saved = Self.loadState()
        picks = saved.picks
        songsByPick = saved.songs
        lookedUpAt = saved.lookedUpAt
        items = Self.loadManifest()
        let stored = UserDefaults.standard.string(forKey: Self.qualityKey).flatMap(WatchDownloadQuality.init(rawValue:))
        quality = stored ?? .recommended
        hasChosenQuality = stored != nil
        backgroundRelay.store = self
        fastRelay.store = self
        reconcileWithDisk()
        matchItems()
        reattachBackgroundTasks()
    }

    // MARK: - Queries

    func item(for key: String) -> Item? {
        items[key]
    }

    func isDownloaded(_ key: String) -> Bool {
        items[key]?.state == .completed
    }

    /// The file for a song that's here, or nil — the earlier copy while a
    /// song is fetched again at a new quality.
    func localURL(for song: WatchSong) -> URL? {
        guard let item = items[song.key] else { return nil }
        let url: URL
        if item.state == .completed {
            url = Self.fileURL(key: item.key, fileExtension: item.fileExtension)
        } else if let previous = item.previousFileExtension {
            url = Self.fileURL(key: item.key, fileExtension: previous)
        } else {
            return nil
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Whether a song can play now: it's here, or its earlier copy is.
    func isPlayable(_ key: String) -> Bool {
        guard let item = items[key] else { return false }
        return item.state == .completed || item.previousFileExtension != nil
    }

    /// The songs of picks, in order, each once.
    func songs(in keys: [String]) -> [WatchSong] {
        var seen = Set<String>()
        return keys.flatMap { songsByPick[$0] ?? [] }.filter { seen.insert($0.key).inserted }
    }

    /// Whether a pick is on the watch — a song also when another pick has it.
    func isOnWatch(_ pick: WatchPick) -> Bool {
        picks.contains(key: pick.key) || (pick.kind == .song && items[WatchKeys.song(source: pick.source, id: pick.id)] != nil)
    }

    /// Songs not here yet, failed ones included: what Fast Download fetches.
    var remainingCount: Int {
        items.values.filter { $0.state != .completed }.count
    }

    var failedCount: Int {
        items.values.filter { $0.state == .failed }.count
    }

    var downloadedCount: Int {
        items.values.filter { $0.state == .completed }.count
    }

    var bytesUsed: Int64 {
        items.values.reduce(0) { $0 + ($1.state == .completed ? $1.fileSize ?? 0 : 0) }
    }

    /// What's coming down on the fast session now, in play order.
    var fastActive: [Item] {
        orderedKeys().compactMap { key in
            tasks[key]?.kind == .fast ? items[key] : nil
        }
    }

    /// Every wanted song's key, newest pick first, each once.
    private func orderedKeys() -> [String] {
        songs(in: picks.items.map(\.key)).map(\.key)
    }

    // MARK: - Picks

    /// Puts something on the watch from its own browsing. Songs already
    /// fetched for it (an album's, opened to pick from) save looking it up.
    func add(_ pick: WatchPick, songs: [WatchSong]? = nil) {
        picks.add(pick)
        if let songs, !songs.isEmpty {
            songsByPick[pick.key] = songs
            unreachable.remove(pick.key)
        }
        picksDidChange(tellPhone: true)
    }

    func remove(key: String) {
        guard picks.contains(key: key) else { return }
        picks.remove(key: key)
        picksDidChange(tellPhone: true)
    }

    /// The iPhone's picks, merged with these. When it was missing something
    /// of the watch's, it hears back.
    func apply(_ theirs: WatchPicks) {
        let merged = picks.merged(with: theirs)
        if merged != picks {
            picks = merged
            picksDidChange(tellPhone: merged != theirs)
        } else if merged != theirs {
            PhoneConnection.shared.send(picks: picks)
        }
    }

    /// Fetches what the picks want now and deletes what they don't, looks
    /// up new ones, and saves at once: this can run in a WatchConnectivity
    /// wake that ends soon after.
    private func picksDidChange(tellPhone: Bool) {
        let keys = Set(picks.items.map(\.key))
        songsByPick = songsByPick.filter { keys.contains($0.key) }
        unreachable.formIntersection(keys)
        matchItems()
        pump()
        saveNow()
        lookUp(picks.items.filter { songsByPick[$0.key] == nil })
        ArtworkStore.shared.prefetch(picks.items.compactMap(\.artworkURL))
        if tellPhone {
            PhoneConnection.shared.send(picks: picks)
        }
    }

    /// New sign-ins: what was looked up with the old ones (Plex streams
    /// carry the token) is looked up again.
    func credentialsDidChange() {
        lookUpAll()
    }

    private func lookUpAll() {
        lookedUpAt = .now
        lookUp(picks.items)
    }

    /// Looks picks up on their servers, one after another, putting each
    /// one's songs on their way as they come. A pick the server couldn't
    /// be asked about keeps the songs it had; so does one that comes back
    /// empty, rather than losing every song to a passing fault.
    private func lookUp(_ wanted: [WatchPick]) {
        let fresh = wanted.filter { !lookingUp.contains($0.key) }
        guard !fresh.isEmpty else { return }
        lookingUp.formUnion(fresh.map(\.key))
        Task { @MainActor in
            for pick in fresh {
                let songs = await WatchLibraryBrowser.shared.songs(for: pick)
                lookingUp.remove(pick.key)
                guard picks.contains(key: pick.key) else { continue }
                if let songs, !songs.isEmpty || songsByPick[pick.key] == nil {
                    songsByPick[pick.key] = songs
                    unreachable.remove(pick.key)
                } else {
                    unreachable.insert(pick.key)
                    logger.error("Couldn't look up \(pick.title, privacy: .public)")
                }
                matchItems()
                pump()
                scheduleSave()
            }
        }
    }

    /// Brings the manifest in line with the picks' songs: deletes what
    /// none holds, gives the rest their latest copy (a fresh stream, a
    /// corrected title), queues what's new.
    private func matchItems() {
        var wanted: [String: WatchSong] = [:]
        for song in songs(in: picks.items.map(\.key)) {
            wanted[song.key] = song
        }
        if fastPhase == .running {
            let unwanted = items.filter { wanted[$0.key] == nil && $0.value.state != .completed }.count
            let new = wanted.keys.filter { items[$0] == nil }.count
            fastTotal = max(fastCompleted, fastTotal - unwanted + new)
        }
        for key in items.keys where wanted[key] == nil {
            delete(key: key)
        }
        for (key, song) in wanted {
            if let item = items[key] {
                if item.song != song {
                    items[key]?.song = song
                }
            } else {
                items[key] = Item(song: song, quality: quality, fileExtension: song.stream(at: quality).fileExtension, state: .queued)
            }
        }
    }

    // MARK: - Quality

    /// Sets what songs come down at; each song here comes down again,
    /// playing its old file meanwhile.
    func setQuality(_ newQuality: WatchDownloadQuality) {
        UserDefaults.standard.set(newQuality.rawValue, forKey: Self.qualityKey)
        hasChosenQuality = true
        guard newQuality != quality else { return }
        quality = newQuality
        for (key, existing) in items where existing.quality != newQuality {
            stopTask(for: key)
            var item = existing
            if item.state == .completed {
                item.previousFileExtension = item.fileExtension
            }
            item.quality = newQuality
            item.fileExtension = item.song.stream(at: newQuality).fileExtension
            item.state = .queued
            item.resumeData = nil
            item.resumeOn = nil
            item.bytesReceived = 0
            item.bytesExpected = 0
            item.error = nil
            item.retries = nil
            items[key] = item
        }
        pump()
        saveNow()
    }

    // MARK: - Fast Download

    /// Fetches everything not here yet on the fast session while Cue is
    /// open: what's queued, what failed, and what the background session
    /// holds (taken off it). `continuing` keeps the count of a run that
    /// stopped when Cue left the screen.
    func startFastDownload(continuing: Bool = false) {
        guard fastPhase != .running else { return }
        var count = 0
        for (key, existing) in items where existing.state != .completed {
            if tasks[key]?.kind == .background {
                stopTask(for: key)
            }
            var item = existing
            item.state = .queued
            item.error = nil
            item.failedOnNetwork = nil
            item.retries = nil
            items[key] = item
            count += 1
        }
        if continuing {
            fastTotal = fastCompleted + count
        } else {
            fastTotal = count
            fastCompleted = 0
        }
        fastBytes = 0
        meter.reset()
        estimator.reset()
        route = .measuring
        bytesPerSecond = nil
        isWaitingForNetwork = false
        resumesFastOnReturn = false
        fastPhase = .running
        logger.info("Fast Download: \(count) songs")
        if !continuing {
            WKInterfaceDevice.current().play(.start)
        }
        startMeter()
        pump()
        scheduleSave()
    }

    /// Stops Fast Download. What's under way starts over on the
    /// background session.
    func stopFastDownload() {
        guard fastPhase == .running else {
            fastPhase = .off
            return
        }
        endFastDownload()
        fastPhase = .off
        pump()
        scheduleSave()
    }

    /// Done with the finished screen.
    func dismissFastDownload() {
        if fastPhase == .finished {
            fastPhase = .off
        }
    }

    private func endFastDownload() {
        meterTask?.cancel()
        meterTask = nil
        bytesPerSecond = nil
        isWaitingForNetwork = false
        for (key, ref) in tasks where ref.kind == .fast {
            tasks[key] = nil
            ref.task.cancel()
            if var item = items[key], item.state == .downloading {
                item.state = .queued
                item.bytesReceived = 0
                items[key] = item
            }
        }
    }

    private func finishFastDownload() {
        meterTask?.cancel()
        meterTask = nil
        bytesPerSecond = nil
        isWaitingForNetwork = false
        fastPhase = .finished
        logger.info("Fast Download finished: \(self.fastCompleted) of \(self.fastTotal), \(self.failedCount) failed")
        WKInterfaceDevice.current().play(failedCount > 0 ? .failure : .success)
    }

    private func startMeter() {
        meterTask?.cancel()
        meterTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.tickMeter()
            }
        }
    }

    /// Once a second: the speed over the last few, and what it says about
    /// the way the songs are coming.
    private func tickMeter() {
        let now = Date.now
        meter.record(total: fastBytes, at: now)
        bytesPerSecond = meter.bytesPerSecond
        route = estimator.update(bytesPerSecond: bytesPerSecond, at: now)
    }

    // MARK: - App lifecycle

    /// Cue left the screen: a Fast Download hands what's left to the
    /// background session, to pick up again on return.
    func appDidEnterBackground() {
        if fastPhase == .running {
            resumesFastOnReturn = true
            endFastDownload()
            fastPhase = .off
            pump()
        }
        saveNow()
    }

    /// Back on screen: picks are looked up again when it's been a while
    /// (or they couldn't be before), the interrupted Fast Download carries
    /// on, and songs that failed for want of a network try again.
    func appDidBecomeActive() {
        if Date.now.timeIntervalSince(lookedUpAt ?? .distantPast) > Self.lookUpInterval {
            lookUpAll()
        } else {
            lookUp(picks.items.filter { songsByPick[$0.key] == nil || unreachable.contains($0.key) })
        }
        if resumesFastOnReturn {
            startFastDownload(continuing: true)
            return
        }
        guard fastPhase != .running else { return }
        var retried = false
        for (key, existing) in items where existing.state == .failed && existing.failedOnNetwork == true {
            var item = existing
            item.state = .queued
            item.error = nil
            item.failedOnNetwork = nil
            item.retries = nil
            items[key] = item
            retried = true
        }
        if retried {
            pump()
            scheduleSave()
        }
    }

    /// The system woke the app for the background session's events. Making
    /// the session hooks its delegate up to them; the handler runs once
    /// they've been delivered.
    ///
    /// If the events already went out while the app was running, that
    /// callback may not come again, so the wake is let go after 25 seconds
    /// regardless; watchOS ends it soon after anyway.
    func handleBackgroundEvents(completion: @escaping () -> Void) {
        backgroundCompletionHandlers.append(completion)
        _ = backgroundSession
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard let self, !self.backgroundCompletionHandlers.isEmpty else { return }
            self.didFinishBackgroundEvents()
        }
    }

    // MARK: - Moving songs

    /// Puts waiting songs on their way, in play order: up to the background
    /// session's share, or the next few on the fast one while Fast Download
    /// runs — finishing the run when nothing's left. Plex conversions go
    /// one at a time, whichever session they're on.
    private func pump() {
        let kind: SessionKind = fastPhase == .running ? .fast : .background
        let limit = kind == .fast ? Self.fastConcurrency : Self.backgroundConcurrency
        let queued = orderedKeys().filter { items[$0]?.state == .queued }
        var running = tasks.values.filter { $0.kind == kind }.count
        var converting = tasks.keys.contains { key in
            items[key].map { $0.song.isPlexConversion(at: $0.quality) } ?? false
        }
        for key in queued where running < limit {
            guard let item = items[key] else { continue }
            if item.song.isPlexConversion(at: item.quality) {
                if converting { continue }
                converting = true
            }
            start(key, on: kind)
            running += 1
        }
        if fastPhase == .running, queued.isEmpty, running == 0, lookingUp.isEmpty {
            finishFastDownload()
        }
    }

    private func start(_ key: String, on kind: SessionKind) {
        guard var item = items[key] else { return }
        stopTask(for: key)
        let session = kind == .fast ? fastSession : backgroundSession
        let task: URLSessionDownloadTask
        if let resumeData = item.resumeData, item.resumeOn == kind {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            // Built now, so it carries the sign-ins as they are now.
            let stream = item.song.stream(at: item.quality)
            item.fileExtension = stream.fileExtension
            item.bytesReceived = 0
            task = session.downloadTask(with: URLRequest(url: stream.url))
        }
        // Key and extension travel with the task, so the relay can put the
        // file in place before the system deletes the temporary copy — even
        // after a relaunch with no manifest in memory.
        task.taskDescription = DownloadTaskName.description(key: key, fileExtension: item.fileExtension)
        task.priority = kind == .fast ? URLSessionTask.highPriority : URLSessionTask.defaultPriority
        tasks[key] = TaskRef(kind: kind, task: task)
        item.state = .downloading
        item.resumeData = nil
        item.resumeOn = nil
        item.error = nil
        item.failedOnNetwork = nil
        items[key] = item
        task.resume()
    }

    private func stopTask(for key: String) {
        tasks.removeValue(forKey: key)?.task.cancel()
    }

    private func delete(key: String) {
        stopTask(for: key)
        if let item = items[key] {
            try? FileManager.default.removeItem(at: Self.fileURL(key: key, fileExtension: item.fileExtension))
            if let previous = item.previousFileExtension {
                try? FileManager.default.removeItem(at: Self.fileURL(key: key, fileExtension: previous))
            }
        }
        items[key] = nil
        lastProgressPublish[key] = nil
    }

    // MARK: - Relay callbacks

    /// Whether an event from this task is about the download as it is now:
    /// its current task, or — before the background session's tasks are
    /// matched back after a relaunch — one the manifest has under way.
    private func accepts(kind: SessionKind, task identifier: Int, key: String) -> Bool {
        if let ref = tasks[key] {
            return ref.kind == kind && ref.task.taskIdentifier == identifier
        }
        return kind == .background && items[key]?.state == .downloading
    }

    fileprivate func didWrite(kind: SessionKind, task identifier: Int, key: String, written: Int64, received: Int64, expected: Int64) {
        guard accepts(kind: kind, task: identifier, key: key), var item = items[key], item.state == .downloading else { return }
        if kind == .fast {
            fastBytes += written
            isWaitingForNetwork = false
        }
        // Bytes arrive many times a second; publish a few times a second.
        let now = Date.now
        guard now.timeIntervalSince(lastProgressPublish[key] ?? .distantPast) > 0.25 || received == expected else { return }
        lastProgressPublish[key] = now
        item.bytesReceived = received
        item.bytesExpected = expected
        items[key] = item
    }

    fileprivate func didWaitForConnectivity(kind: SessionKind, task identifier: Int, key: String) {
        guard kind == .fast, accepts(kind: kind, task: identifier, key: key) else { return }
        isWaitingForNetwork = true
    }

    /// A file landed, already moved into place by the relay. It's the song
    /// whichever task brought it; any other task for it is let go. One no
    /// pick wants any more is deleted.
    fileprivate func didFinish(kind: SessionKind, task identifier: Int, key: String, fileExtension: String, fileSize: Int64?) {
        guard var item = items[key] else {
            try? FileManager.default.removeItem(at: Self.fileURL(key: key, fileExtension: fileExtension))
            return
        }
        guard item.state != .completed else { return }
        if let ref = tasks.removeValue(forKey: key), ref.kind != kind || ref.task.taskIdentifier != identifier {
            ref.task.cancel()
        }
        // The copy at the old quality goes once the new one is in place (a
        // new one with the same suffix has already replaced it).
        if let previous = item.previousFileExtension, previous != fileExtension {
            try? FileManager.default.removeItem(at: Self.fileURL(key: key, fileExtension: previous))
        }
        item.previousFileExtension = nil
        item.state = .completed
        item.fileExtension = fileExtension
        item.fileSize = fileSize
        item.bytesReceived = fileSize ?? item.bytesExpected
        item.resumeData = nil
        item.resumeOn = nil
        item.error = nil
        item.retries = nil
        items[key] = item
        lastProgressPublish[key] = nil
        if fastPhase == .running {
            fastCompleted += 1
        }
        pump()
        scheduleSave()
    }

    fileprivate func didFail(kind: SessionKind, task identifier: Int, key: String, error: Error, resumeData: Data?) {
        guard accepts(kind: kind, task: identifier, key: key), var item = items[key], item.state == .downloading else { return }
        tasks[key] = nil
        let nsError = error as NSError
        let cancelled = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
        item.resumeData = resumeData
        item.resumeOn = resumeData == nil ? nil : kind
        if cancelled {
            // Not this store's doing (its own cancels are stale by the time
            // they report): the system's, after a force quit say. Back in
            // line, rather than failed until the app is next opened.
            item.state = .queued
        } else if Self.isBrokenOff(nsError), (item.retries ?? 0) < Self.retryLimit {
            item.state = .queued
            item.retries = (item.retries ?? 0) + 1
        } else {
            item.state = .failed
            item.error = error.localizedDescription
            item.failedOnNetwork = Self.isNetworkFailure(nsError) || Self.isBrokenOff(nsError)
        }
        items[key] = item
        logger.error("\(item.song.title, privacy: .public) failed on the \(kind.rawValue, privacy: .public) session: \(error.localizedDescription, privacy: .public)")
        pump()
        scheduleSave()
    }

    fileprivate func didFinishBackgroundEvents() {
        saveNow()
        let handlers = backgroundCompletionHandlers
        backgroundCompletionHandlers = []
        handlers.forEach { $0() }
    }

    /// The server broke off a response before or while sending it — what
    /// a Plex conversion does when the transcoder is busy or restarted.
    /// Worth trying again by itself.
    private static func isBrokenOff(_ error: NSError) -> Bool {
        error.domain == NSURLErrorDomain && [
            NSURLErrorCannotParseResponse,
            NSURLErrorBadServerResponse,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorZeroByteResource,
        ].contains(error.code)
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
            NSURLErrorDataNotAllowed,
            NSURLErrorCannotLoadFromNetwork,
            NSURLErrorBackgroundSessionWasDisconnected,
            NSURLErrorSecureConnectionFailed,
        ].contains(error.code)
    }

    // MARK: - Startup

    /// Matches what the background session is still carrying back to the
    /// manifest, puts back in line what the manifest has under way that no
    /// session holds (the fast session dies with the app), and lets go of
    /// tasks for songs that are gone.
    private func reattachBackgroundTasks() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let carried = await self.backgroundSession.allTasks.filter { $0.state != .completed }
            var newest: [String: URLSessionTask] = [:]
            for task in carried {
                guard let key = DownloadTaskName.parse(task.taskDescription)?.key else {
                    task.cancel()
                    continue
                }
                if let other = newest[key] {
                    let (keep, drop) = other.taskIdentifier > task.taskIdentifier ? (other, task) : (task, other)
                    drop.cancel()
                    newest[key] = keep
                } else {
                    newest[key] = task
                }
            }
            for (key, task) in newest {
                guard self.tasks[key] == nil, let item = self.items[key], item.state == .downloading || item.state == .queued else {
                    if self.tasks[key]?.task !== task { task.cancel() }
                    continue
                }
                self.tasks[key] = TaskRef(kind: .background, task: task)
                self.items[key]?.state = .downloading
            }
            for (key, item) in self.items where item.state == .downloading && self.tasks[key] == nil {
                self.items[key]?.state = .queued
            }
            self.pump()
            self.scheduleSave()
        }
    }

    /// A finished song whose file has gone is fetched again; a file that
    /// landed while the manifest was unsaved is taken as finished; files no
    /// entry owns are deleted.
    private func reconcileWithDisk() {
        for (key, existing) in items {
            let url = Self.fileURL(key: key, fileExtension: existing.fileExtension)
            var item = existing
            if item.state == .completed, !FileManager.default.fileExists(atPath: url.path) {
                item.state = .queued
                item.bytesReceived = 0
                item.fileSize = nil
            } else if item.state != .completed, item.previousFileExtension != item.fileExtension, let size = Self.size(of: url) {
                // Landed while the manifest was unsaved. Not when the file
                // there is the old copy of a song being converted within one
                // format (256 to 128 kbps MP3, say), which shares its name.
                item.state = .completed
                item.fileSize = size
                item.resumeData = nil
                item.resumeOn = nil
            }
            if let previous = item.previousFileExtension {
                let previousURL = Self.fileURL(key: key, fileExtension: previous)
                if item.state == .completed {
                    if previous != item.fileExtension {
                        try? FileManager.default.removeItem(at: previousURL)
                    }
                    item.previousFileExtension = nil
                } else if !FileManager.default.fileExists(atPath: previousURL.path) {
                    item.previousFileExtension = nil
                }
            }
            items[key] = item
        }
        let owned = Set(items.values.flatMap { item in
            [item.fileExtension, item.previousFileExtension].compactMap { $0 }.map { Self.fileURL(key: item.key, fileExtension: $0).lastPathComponent }
        })
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent != Self.manifestURL.lastPathComponent && !owned.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Storage

    /// The picks and what they were last looked up as.
    private struct SavedState: Codable {
        var picks: WatchPicks
        var songs: [String: [WatchSong]]
        var lookedUpAt: Date?
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

    nonisolated private static var stateURL: URL {
        directory.deletingLastPathComponent().appendingPathComponent("picks.json")
    }

    nonisolated static func size(of url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    /// Protected until first unlock, so a background relaunch can write,
    /// and left out of backups: the songs are fetched again on demand.
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
        // Left by the version that took whole libraries from the iPhone.
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent().appendingPathComponent("library.json"))
    }

    private static func loadManifest() -> [String: Item] {
        guard let data = try? Data(contentsOf: manifestURL),
              let items = try? JSONDecoder().decode([Item].self, from: data) else { return [:] }
        return Dictionary(items.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func loadState() -> SavedState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else {
            return SavedState(picks: .empty, songs: [:])
        }
        return state
    }

    /// Coalesces saves: progress alone never writes, and a burst of
    /// changes (an album landing) writes once.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        if let data = try? JSONEncoder().encode(Array(items.values)) {
            try? data.write(to: Self.manifestURL, options: options)
        }
        if let data = try? JSONEncoder().encode(SavedState(picks: picks, songs: songsByPick, lookedUpAt: lookedUpAt)) {
            try? data.write(to: Self.stateURL, options: options)
        }
    }
}

/// How a download is named on its session task: `<key>|<extension>`.
enum DownloadTaskName {
    static func description(key: String, fileExtension: String) -> String {
        "\(key)|\(fileExtension)"
    }

    static func parse(_ description: String?) -> (key: String, fileExtension: String)? {
        guard let description else { return nil }
        let parts = description.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }
}

/// A session's delegate. Off the main actor, because the session calls it
/// on its own queue and a finished file has to be moved out of its
/// temporary place before the call returns.
private final class DownloadRelay: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let kind: WatchDownloadStore.SessionKind
    weak var store: WatchDownloadStore?
    private let logger = Logger(subsystem: "dance.cue.watch", category: "Downloads")

    init(kind: WatchDownloadStore.SessionKind) {
        self.kind = kind
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let key = DownloadTaskName.parse(downloadTask.taskDescription)?.key else { return }
        let identifier = downloadTask.taskIdentifier
        let kind = kind
        Task { @MainActor in
            self.store?.didWrite(kind: kind, task: identifier, key: key, written: bytesWritten, received: totalBytesWritten, expected: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        guard let key = DownloadTaskName.parse(task.taskDescription)?.key else { return }
        let identifier = task.taskIdentifier
        let kind = kind
        Task { @MainActor in
            self.store?.didWaitForConnectivity(kind: kind, task: identifier, key: key)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (key, fileExtension) = DownloadTaskName.parse(downloadTask.taskDescription) else { return }
        let identifier = downloadTask.taskIdentifier
        let kind = kind
        // A refused request (a stale token, a transcode the server can't
        // do) still lands here as a finished file: a short error page. Fail
        // it rather than keep the page as a song.
        if let refusal = Self.refusal(in: downloadTask.response) {
            Task { @MainActor in
                self.store?.didFail(kind: kind, task: identifier, key: key, error: refusal, resumeData: nil)
            }
            return
        }
        let destination = WatchDownloadStore.fileURL(key: key, fileExtension: fileExtension)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        } catch {
            Task { @MainActor in
                self.store?.didFail(kind: kind, task: identifier, key: key, error: error, resumeData: nil)
            }
            return
        }
        let size = WatchDownloadStore.size(of: destination)
        Task { @MainActor in
            self.store?.didFinish(kind: kind, task: identifier, key: key, fileExtension: fileExtension, fileSize: size)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let key = DownloadTaskName.parse(task.taskDescription)?.key else { return }
        let identifier = task.taskIdentifier
        let kind = kind
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Task { @MainActor in
            self.store?.didFail(kind: kind, task: identifier, key: key, error: error, resumeData: resumeData)
        }
    }

    /// Which way each transfer went, for the console: watchOS keeps that to
    /// itself, and these are the clues — a proxied connection is the iPhone
    /// relaying it, a LAN address the watch's own Wi‑Fi.
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let transaction = metrics.transactionMetrics.last else { return }
        let seconds = metrics.taskInterval.duration
        let bytes = transaction.countOfResponseBodyBytesReceived
        let rate = seconds > 0 ? Double(bytes) / seconds : 0
        let local = transaction.localAddress ?? "?"
        let remote = transaction.remoteAddress ?? "?"
        logger.info("\(self.kind.rawValue, privacy: .public) transfer: \(bytes) bytes at \(Int(rate / 1000)) KB/s, proxy \(transaction.isProxyConnection), cellular \(transaction.isCellular), local \(local, privacy: .public), remote \(remote, privacy: .public)")
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.store?.didFinishBackgroundEvents()
        }
    }

    struct Refused: LocalizedError {
        let statusCode: Int
        let mimeType: String?

        var errorDescription: String? {
            if (400 ..< 500).contains(statusCode) {
                return "The server refused the song (HTTP \(statusCode))."
            }
            if statusCode >= 500 {
                return "The server couldn't send the song (HTTP \(statusCode))."
            }
            return "The server sent a page instead of a song\(mimeType.map { " (\($0))" } ?? "")."
        }
    }

    /// The error for a response that isn't audio, or nil when it may be.
    static func refusal(in response: URLResponse?) -> Refused? {
        guard let http = response as? HTTPURLResponse else { return nil }
        let mime = http.mimeType?.lowercased()
        if !(200 ..< 300).contains(http.statusCode) {
            return Refused(statusCode: http.statusCode, mimeType: mime)
        }
        if let mime, mime.hasPrefix("text/") || mime.hasSuffix("/xml") || mime.hasSuffix("/json") || mime.hasSuffix("+xml") {
            return Refused(statusCode: http.statusCode, mimeType: mime)
        }
        return nil
    }
}
