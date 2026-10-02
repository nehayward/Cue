import Defaults
import Foundation
import MusicSearchKit
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
/// the watch is the Music app's to download (MusicKit has no player on
/// watchOS).
///
/// Songs go at the watch's own quality (`WatchDownloadQuality`), not the
/// iPhone's Streaming Quality: each is kept as a `WatchTrackSource`, and its
/// stream built from that, so a new quality rebuilds every stream and the
/// watch converts what it has.
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
    /// How songs come down to the watch; nil until the person picks.
    private(set) var quality: WatchDownloadQuality?

    /// What songs go at: the chosen quality, or the recommended one.
    var effectiveQuality: WatchDownloadQuality { quality ?? .recommended }

    /// Nobody has picked a quality yet, so the first add asks.
    var needsQualityChoice: Bool { quality == nil }

    /// A watch is paired and has Cue on it, so music can be put there.
    var isAvailable: Bool { isPaired && isWatchAppInstalled }

    @ObservationIgnored private let logger = Logger(subsystem: "dance.cue", category: "WatchSync")
    /// The session's delegate, kept alive here; nil where there's no
    /// WatchConnectivity.
    @ObservationIgnored private var relay: AnyObject?
    /// Every song in the library as the iPhone knows it, by key — what its
    /// stream is built from.
    @ObservationIgnored private var sources: [String: WatchTrackSource]

    private init() {
        library = Self.loadLibrary()
        status = Self.loadStatus()
        sources = Self.loadSources()
        quality = UserDefaults.standard.string(forKey: AppStorageKeys.watchDownloadQuality).flatMap(WatchDownloadQuality.init(rawValue:))
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

    /// Reads whether a watch is paired and has Cue straight from the
    /// session — for a request from the watch that woke Cue, which can come
    /// in before the activation report has been taken in.
    func refreshSessionState() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
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
            guard let source = WatchTrackSource(item) else { return 0 }
            sources[source.key] = source
            library.addSongs([source.track(at: effectiveQuality)], at: .now)
            libraryDidChange()
            return 1
        }

        let key = DownloadManager.containerKey(for: item)
        guard !addingKeys.contains(key) else { return 0 }
        addingKeys.insert(key)
        defer { addingKeys.remove(key) }

        let fetched = await LocalPlaybackService.shared.allContainerTracks(for: item)
        var seen = Set<String>()
        let found = fetched.compactMap { WatchTrackSource($0) }.filter { seen.insert($0.key).inserted }
        guard !found.isEmpty else { return 0 }
        for source in found {
            sources[source.key] = source
        }
        let tracks = found.map { $0.track(at: effectiveQuality) }
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

    /// Sets how songs come down to the watch, and rebuilds every song's
    /// stream for it. The watch fetches each again, playing the old file
    /// until the new one lands; a song with no source (put there before
    /// sources were kept) stays as it is until it's added again.
    func setQuality(_ newQuality: WatchDownloadQuality) {
        UserDefaults.standard.set(newQuality.rawValue, forKey: AppStorageKeys.watchDownloadQuality)
        guard newQuality != quality else { return }
        quality = newQuality
        var changed = false
        for (key, track) in library.tracks {
            guard let source = sources[key] else { continue }
            let rebuilt = source.track(at: newQuality)
            if rebuilt != track {
                library.tracks[key] = rebuilt
                changed = true
            }
        }
        if changed {
            libraryDidChange()
        }
    }

    private func libraryDidChange() {
        library.bumpRevision()
        saveLibrary()
        send()
    }

    // MARK: - Session

    /// Sends the library as it is now, as application context — or, when
    /// it's too big for that, as a file, in place of any older copy still
    /// waiting to go. File transfers never arrive between simulators, so
    /// context is the way that works everywhere; a file stays until its
    /// transfer finishes (the system reads it as it goes).
    private func send() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let session = WCSession.default
        guard session.activationState == .activated, isAvailable else { return }
        for transfer in session.outstandingFileTransfers where WatchSyncMessage.isLibrary(transfer.file.metadata) {
            transfer.cancel()
        }
        Self.clearOutgoing()
        do {
            if let context = try WatchSyncMessage.libraryContext(library) {
                try session.updateApplicationContext(context)
                logger.info("Sent the watch library as context, revision \(self.library.revision), \(self.library.tracks.count) songs")
                return
            }
        } catch {
            logger.error("Couldn't send the watch library as context, sending a file: \(error.localizedDescription, privacy: .public)")
        }
        let url = Self.outgoingDirectory.appendingPathComponent("library-\(library.revision).json")
        do {
            try FileManager.default.createDirectory(at: Self.outgoingDirectory, withIntermediateDirectories: true)
            try library.encoded().write(to: url, options: .atomic)
        } catch {
            logger.error("Couldn't write the watch library: \(error.localizedDescription, privacy: .public)")
            return
        }
        session.transferFile(url, metadata: WatchSyncMessage.libraryMetadata(revision: library.revision))
        logger.info("Sent the watch library as a file, revision \(self.library.revision), \(self.library.tracks.count) songs")
        #endif
    }

    /// Sends the library when the watch is behind it and no copy is on its
    /// way: after a reinstall, a first pairing, or a transfer that failed.
    /// A watch ahead of this library (an iPhone restored from an older
    /// backup) would ignore it, so the revision moves past the watch's
    /// first; otherwise the two would trade the same copy and status
    /// forever.
    private func sendIfWatchIsBehind() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let session = WCSession.default
        guard session.activationState == .activated, isAvailable else { return }
        // Nothing to send to a watch that has nothing and should have nothing.
        guard library.revision > 0 else { return }
        let watchRevision = status?.libraryRevision ?? 0
        if watchRevision > library.revision {
            library.revision = watchRevision
            libraryDidChange()
            return
        }
        guard watchRevision < library.revision else { return }
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

    /// Saves the library, and the sources of the songs it still holds.
    private func saveLibrary() {
        sources = sources.filter { library.tracks[$0.key] != nil }
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try library.encoded().write(to: Self.libraryURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try JSONEncoder().encode(Array(sources.values)).write(to: Self.sourcesURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            logger.error("Couldn't save the watch library: \(error.localizedDescription)")
        }
    }

    private static var sourcesURL: URL {
        directory.appendingPathComponent("sources.json")
    }

    private static func loadSources() -> [String: WatchTrackSource] {
        guard let data = try? Data(contentsOf: sourcesURL),
              let sources = try? JSONDecoder().decode([WatchTrackSource].self, from: data) else { return [:] }
        return Dictionary(sources.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
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

    /// The watch browsing this iPhone's libraries, or putting something on
    /// itself from them (`WatchBrowseServer`).
    func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        guard let request = try? WatchRequest.decoded(from: messageData) else {
            replyHandler((try? WatchReply.failed("Update Cue on your iPhone.").encoded()) ?? Data())
            return
        }
        Task { @MainActor in
            let reply = await WatchBrowseServer.shared.reply(to: request)
            replyHandler((try? reply.encoded()) ?? Data())
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

/// A Plex or Subsonic song as the iPhone knows it: what the watch shows,
/// and what its stream is built from at whatever quality the watch is set
/// to — saved under the download manager's key.
struct WatchTrackSource: Codable {
    let key: String
    let service: MusicService
    let contentID: String
    /// The original file (`previewURL`).
    let sourceURL: URL
    let audioCodec: String?
    let title: String
    let artist: String
    let album: String?
    let artworkURL: URL?
    let duration: TimeInterval?

    /// Nil for anything the download manager can't take.
    @MainActor
    init?(_ item: PlayableContent) {
        guard DownloadManager.shared.canDownload(item), let sourceURL = item.previewURL else { return nil }
        key = DownloadManager.key(for: item)
        service = item.content.service
        contentID = item.content.id
        self.sourceURL = sourceURL
        audioCodec = item.metadata?.audioCodec
        title = item.title
        artist = item.metadata?.artist ?? item.subtitle
        album = item.metadata?.album
        artworkURL = item.thumbnail ?? item.artwork
        duration = item.metadata?.duration.map { Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18 }
    }

    /// The song as the watch fetches it at `quality`: converted to MP3 by
    /// the server, or the original file.
    func track(at quality: WatchDownloadQuality) -> WatchTrack {
        let format: StreamTranscoding.Format = quality.bitrate == nil ? .original : .mp3
        let bitrate = quality.bitrate ?? StreamTranscoding.defaultBitrate
        let url = DeviceStream.url(service: service, contentID: contentID, sourceURL: sourceURL, audioCodec: audioCodec, format: format, bitrate: bitrate)
        let fromURL = url.pathExtension.lowercased()
        let fileExtension = DeviceStream.fileExtension(service: service, audioCodec: audioCodec, format: format).flatMap { $0.isEmpty || $0.count > 5 ? nil : $0 }
            ?? (fromURL.isEmpty ? "mp3" : fromURL)
        return WatchTrack(
            key: key,
            title: title,
            artist: artist,
            album: album,
            artworkURL: artworkURL,
            streamURL: url,
            fileExtension: fileExtension,
            duration: duration
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
