import Foundation
import Observation
import OSLog
import SonosKit
import WatchSync
#if os(iOS) && !targetEnvironment(macCatalyst)
import WatchConnectivity
#endif

/// Puts Plex and Subsonic music on the Apple Watch.
///
/// The iPhone keeps the list — a `WatchLibrary` of the albums, playlists,
/// artists and songs the person chose, each song with the stream URL it
/// comes from — and sends it whole to the watch after every change. The
/// watch downloads the files from the server itself rather than through the
/// iPhone, which is what lets its Fast Download mode run over its own Wi‑Fi
/// with Bluetooth off (see the watch's `WatchDownloadStore`). It answers
/// with a `WatchStatus`, so this side can say how much has landed.
///
/// The same services the download manager takes, for the same reason: a
/// Plex or Subsonic song is a plain URL anything can fetch. Apple Music on
/// the watch is the Music app's to download.
///
/// Inert where there's no watch to pair (iPad, Mac, Vision Pro): nothing
/// is available, so no menu offers it.
@MainActor
@Observable
final class WatchSyncService {
    static let shared = WatchSyncService()

    /// What's on the watch, or on its way there.
    private(set) var library: WatchLibrary
    /// What the watch last said it has.
    private(set) var status: WatchStatus?
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false
    /// Albums whose songs are being fetched to go on the watch.
    private(set) var addingKeys: Set<String> = []

    /// A watch is paired and has Cue on it, so music can be put there.
    var isAvailable: Bool { isPaired && isWatchAppInstalled }

    @ObservationIgnored private let logger = Logger(subsystem: "dance.cue", category: "WatchSync")
    /// The session's delegate, kept alive here; nil where there's no
    /// WatchConnectivity.
    @ObservationIgnored private var relay: AnyObject?

    private init() {
        library = Self.loadLibrary()
        status = Self.loadStatus()
    }

    /// Starts the session, once, at launch.
    func activate() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard WCSession.isSupported(), relay == nil else { return }
        let relay = WatchSessionRelay()
        relay.service = self
        self.relay = relay
        WCSession.default.delegate = relay
        WCSession.default.activate()
        #endif
    }

    // MARK: - Queries

    /// Whether this can go on the watch: a Plex or Subsonic song with its
    /// stream, or an album, playlist or artist of them — what the download
    /// manager takes — and a watch with Cue to put it on.
    func canAdd(_ item: PlayableContent) -> Bool {
        guard isAvailable else { return false }
        let downloads = DownloadManager.shared
        return item.content.type == .track ? downloads.canDownload(item) : downloads.canDownload(contentsOf: item)
    }

    /// Whether this album, playlist or artist is on the watch whole, or
    /// this song is among its Songs.
    func isOnWatch(_ item: PlayableContent) -> Bool {
        if item.content.type == .track {
            return library.collection(key: WatchCollection.songsKey)?.trackKeys.contains(DownloadManager.key(for: item)) == true
        }
        return library.collection(key: DownloadManager.containerKey(for: item)) != nil
    }

    func isAdding(_ item: PlayableContent) -> Bool {
        addingKeys.contains(DownloadManager.containerKey(for: item))
    }

    /// How many of a collection's songs the watch has, by its last report.
    func downloadedCount(of collection: WatchCollection) -> Int {
        status?.downloadedByCollection[collection.key] ?? 0
    }

    /// Songs the library holds, each once.
    var songCount: Int { library.tracks.count }

    // MARK: - Changing what's on the watch

    /// Puts an album, playlist or artist on the watch whole — its songs as
    /// they are now, every page of them — or a song among its Songs. Adding
    /// what's already there refreshes it: a playlist picks up its new songs,
    /// and every song a fresh stream URL. Returns how many songs it put
    /// there; 0 means nothing could go.
    @discardableResult
    func add(_ item: PlayableContent) async -> Int {
        guard canAdd(item) else { return 0 }
        if item.content.type == .track {
            guard let track = WatchTrack(item) else { return 0 }
            library.addSongs([track], at: .now)
            libraryDidChange()
            return 1
        }

        let key = DownloadManager.containerKey(for: item)
        guard !addingKeys.contains(key) else { return 0 }
        addingKeys.insert(key)
        defer { addingKeys.remove(key) }

        let fetched = await LocalPlaybackService.shared.allContainerTracks(for: item)
        var seen = Set<String>()
        let tracks = fetched.compactMap { WatchTrack($0) }.filter { seen.insert($0.key).inserted }
        guard !tracks.isEmpty else { return 0 }
        let collection = WatchCollection(
            key: key,
            kind: WatchCollection.Kind(item.content.type),
            title: item.title,
            subtitle: item.metadata?.artist ?? item.subtitle,
            artworkURL: item.thumbnail ?? item.artwork,
            addedAt: library.collection(key: key)?.addedAt ?? .now,
            trackKeys: tracks.map(\.key)
        )
        library.upsert(collection, tracks: tracks)
        libraryDidChange()
        return tracks.count
    }

    /// Takes an album, playlist or artist off the watch, or a song out of
    /// its Songs. The watch deletes the files no collection holds any more.
    func remove(_ item: PlayableContent) {
        if item.content.type == .track {
            library.removeSong(key: DownloadManager.key(for: item))
        } else {
            library.removeCollection(key: DownloadManager.containerKey(for: item))
        }
        libraryDidChange()
    }

    func removeCollection(key: String) {
        library.removeCollection(key: key)
        libraryDidChange()
    }

    func removeAll() {
        library.collections.removeAll()
        library.tracks.removeAll()
        libraryDidChange()
    }

    private func libraryDidChange() {
        library.bumpRevision()
        saveLibrary()
        send()
    }

    // MARK: - Session

    /// Sends the library as it is now, in place of any older copy still
    /// waiting to go. The file stays until the transfer finishes (the
    /// system reads it as it goes); older ones are cleared as new go out.
    private func send() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let session = WCSession.default
        guard session.activationState == .activated, isAvailable else { return }
        for transfer in session.outstandingFileTransfers where WatchSyncMessage.isLibrary(transfer.file.metadata) {
            transfer.cancel()
        }
        Self.clearOutgoing()
        let url = Self.outgoingDirectory.appendingPathComponent("library-\(library.revision).json")
        do {
            try FileManager.default.createDirectory(at: Self.outgoingDirectory, withIntermediateDirectories: true)
            try library.encoded().write(to: url, options: .atomic)
        } catch {
            logger.error("Couldn't write the watch library: \(error.localizedDescription)")
            return
        }
        session.transferFile(url, metadata: WatchSyncMessage.libraryMetadata(revision: library.revision))
        logger.info("Sent the watch library, revision \(self.library.revision), \(self.library.tracks.count) songs")
        #endif
    }

    /// Sends the library when the watch is behind it and no copy is on its
    /// way: after a reinstall, a first pairing, or a transfer that failed.
    private func sendIfWatchIsBehind() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let session = WCSession.default
        guard session.activationState == .activated, isAvailable else { return }
        // Nothing to send to a watch that has nothing and should have nothing.
        guard library.revision > 0 else { return }
        guard status?.libraryRevision != library.revision else { return }
        let pending = session.outstandingFileTransfers.contains { transfer in
            WatchSyncMessage.isLibrary(transfer.file.metadata)
                && WatchSyncMessage.revision(in: transfer.file.metadata) == library.revision
        }
        if !pending { send() }
        #endif
    }

    fileprivate func sessionStateDidChange(isPaired: Bool, isWatchAppInstalled: Bool) {
        self.isPaired = isPaired
        self.isWatchAppInstalled = isWatchAppInstalled
        sendIfWatchIsBehind()
    }

    fileprivate func didReceive(status: WatchStatus) {
        self.status = status
        Self.saveStatus(status)
        sendIfWatchIsBehind()
    }

    /// A copy that didn't make it is put right when the watch next
    /// reports a revision behind this one (`sendIfWatchIsBehind`); one
    /// cancelled for a newer copy needs nothing.
    fileprivate func transferDidFinish(revision: Int?, error: Error?) {
        guard let error, revision == library.revision else { return }
        logger.error("Library transfer \(revision ?? -1) didn't make it: \(error.localizedDescription)")
    }

    // MARK: - Storage

    private static var directory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("AppleWatch", isDirectory: true)
    }

    private static var libraryURL: URL {
        directory.appendingPathComponent("library.json")
    }

    private static var outgoingDirectory: URL {
        directory.appendingPathComponent("Outgoing", isDirectory: true)
    }

    private static let statusKey = "watchSync.status"

    private static func loadLibrary() -> WatchLibrary {
        guard let data = try? Data(contentsOf: libraryURL) else { return .empty }
        return (try? WatchLibrary.decoded(from: data)) ?? .empty
    }

    private func saveLibrary() {
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try library.encoded().write(to: Self.libraryURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            logger.error("Couldn't save the watch library: \(error.localizedDescription)")
        }
    }

    private static func loadStatus() -> WatchStatus? {
        guard let data = UserDefaults.standard.data(forKey: statusKey) else { return nil }
        return try? JSONDecoder().decode(WatchStatus.self, from: data)
    }

    private static func saveStatus(_ status: WatchStatus) {
        UserDefaults.standard.set(try? JSONEncoder().encode(status), forKey: statusKey)
    }

    private static func clearOutgoing() {
        let files = (try? FileManager.default.contentsOfDirectory(at: outgoingDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst)
/// The session's delegate, off the main actor because WatchConnectivity
/// calls it on its own queue; everything it hears goes to the service.
private final class WatchSessionRelay: NSObject, WCSessionDelegate, @unchecked Sendable {
    weak var service: WatchSyncService?

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        let status = WatchSyncMessage.status(in: session.receivedApplicationContext)
        Task { @MainActor in
            if let status { self.service?.didReceive(status: status) }
            self.service?.sessionStateDidChange(isPaired: paired, isWatchAppInstalled: installed)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switching to another watch: activate again for the new one.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor in
            self.service?.sessionStateDidChange(isPaired: paired, isWatchAppInstalled: installed)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let status = WatchSyncMessage.status(in: applicationContext) else { return }
        Task { @MainActor in
            self.service?.didReceive(status: status)
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let revision = WatchSyncMessage.revision(in: fileTransfer.file.metadata)
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        Task { @MainActor in
            self.service?.transferDidFinish(revision: revision, error: error)
        }
    }
}
#endif

extension WatchTrack {
    /// A Plex or Subsonic song as the watch fetches it: the stream this
    /// device would download (Streaming Quality applied), saved under the
    /// download manager's key and extension. Nil for anything else.
    @MainActor
    init?(_ item: PlayableContent) {
        guard DownloadManager.shared.canDownload(item), let url = item.playbackStreamURL else { return nil }
        self.init(
            key: DownloadManager.key(for: item),
            title: item.title,
            artist: item.metadata?.artist ?? item.subtitle,
            album: item.metadata?.album,
            artworkURL: item.thumbnail ?? item.artwork,
            streamURL: url,
            fileExtension: DownloadNaming.fileExtension(for: item, url: url),
            duration: item.metadata?.duration.map { Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18 }
        )
    }
}

extension WatchCollection.Kind {
    init(_ type: ContentType) {
        switch type {
        case .playlist: self = .playlist
        case .artist: self = .artist
        default: self = .album
        }
    }
}
