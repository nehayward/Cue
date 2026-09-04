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
        let url: URL
        let fileExtension: String
        let createdAt: Date
        var state: State
        var bytesReceived: Int64 = 0
        var bytesExpected: Int64 = 0
        var fileSize: Int64?
        var resumeData: Data?
        var error: String?

        var id: String { key }

        var progress: Double {
            guard bytesExpected > 0 else { return 0 }
            return min(1, Double(bytesReceived) / Double(bytesExpected))
        }

        var isActive: Bool {
            state == .queued || state == .downloading
        }
    }

    /// Every download, complete or not, by key.
    private(set) var items: [String: Item] = [:]

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
        relay.manager = self
        adoptLegacyPlexDownloads()
        reconcileWithDisk()
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
    /// way the local queue fetches it, as one batch the system shows and
    /// keeps running. Without Super the batch fills the free slots that are
    /// left, in the container's order, and reports what it couldn't take.
    @discardableResult
    func download(contentsOf container: PlayableContent) async -> BatchResult {
        let tracks = await LocalPlaybackService.shared.containerTracks(for: container)
        let downloadable = tracks.filter { canDownload($0) && !isDownloaded($0) }
        guard !downloadable.isEmpty else { return BatchResult() }
        var result = BatchResult()
        var keys: [String] = []
        for track in downloadable {
            if takesNewSlot(track), isAtFreeLimit {
                result.heldBack += 1
                continue
            }
            queue(track)
            keys.append(Self.key(for: track))
            result.queued += 1
        }
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

    /// `download(_:)` without the batch bookkeeping, for callers that batch
    /// themselves.
    private func queue(_ item: PlayableContent) {
        guard canDownload(item), let url = item.previewURL else { return }
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
            state: .queued
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
            for task in tasks where task.taskDescription?.hasPrefix(key + "|") == true {
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
            for task in tasks where task.taskDescription?.hasPrefix(key + "|") == true {
                task.cancel()
            }
        }
        try? FileManager.default.removeItem(at: Self.fileURL(key: entry.key, fileExtension: entry.fileExtension))
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
        scheduleSave()
    }

    func removeAllCompleted() {
        for entry in completed {
            try? FileManager.default.removeItem(at: Self.fileURL(key: entry.key, fileExtension: entry.fileExtension))
            items[entry.key] = nil
        }
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
        task.taskDescription = "\(entry.key)|\(entry.fileExtension)"
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
            let carried = Set(tasks.compactMap { $0.taskDescription?.split(separator: "|").first.map(String.init) })
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

    /// Filesystem-safe key for a track: its service and id with path
    /// separators and the extension dot neutralized. Plex keeps the bare id
    /// the first build used, so its downloads carry over.
    static func key(for item: PlayableContent) -> String {
        let id = item.content.id
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return item.content.service == .plex ? id : "\(item.content.service.sonosRawValue)-\(id)"
    }

    private static func fileExtension(for item: PlayableContent, url: URL) -> String {
        let fromMetadata = item.metadata?.audioCodec?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        if !fromMetadata.isEmpty, fromMetadata.count <= 5 { return fromMetadata }
        let fromURL = url.pathExtension.lowercased()
        return fromURL.isEmpty ? "mp3" : fromURL
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

    /// Coalesces saves: progress alone never writes, and bursts of state
    /// changes (an album finishing) write once.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            let snapshot = Array(self.items.values)
            await Task.detached(priority: .utility) {
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                try? data.write(to: Self.manifestURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
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
        guard let description = task.taskDescription else { return nil }
        let parts = description.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let (key, _) = key(of: downloadTask) else { return }
        Task { @MainActor in
            self.manager?.didWrite(key: key, received: totalBytesWritten, expected: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (key, fileExtension) = key(of: downloadTask) else { return }
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
