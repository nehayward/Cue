import Foundation
import MusicSearchKit
import Observation
import OSLog
import SonosKit
import WatchSync
#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit
import WatchConnectivity
#endif

/// Puts Plex and Subsonic music on the Apple Watch, and lets the watch get
/// its own.
///
/// Both devices keep the same list — a `WatchLibrary` of the albums,
/// playlists, artists and songs on the watch, each song with where it comes
/// from — and either changes it: this iPhone from Add to Apple Watch, the
/// watch from its own browsing. Every change makes a new revision and goes
/// across whole as application context; the newer revision wins. The watch
/// downloads the files from the server itself, which is what lets its Fast
/// Download run over its own Wi‑Fi with Bluetooth off, and answers with a
/// `WatchStatus` so this side can say how much has landed.
///
/// The watch browses and downloads with MusicSearchKit and the sign-ins this
/// iPhone shares (`WatchCredentials`), sent with the library and again
/// whenever they change, so it needs no iPhone in reach.
///
/// Songs go at the library's quality (`WatchDownloadQuality`), not this
/// iPhone's Streaming Quality, and keep their origin, so a new quality
/// rebuilds every stream on whichever device chose it (`ConvertedStream`)
/// and the watch converts what it has. Only Plex and Subsonic, as with the
/// download manager: their songs are plain URLs. Apple Music on the watch is
/// the Music app's (MusicKit has no player on watchOS).
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

    /// What songs go at: the chosen quality, or the recommended one.
    var effectiveQuality: WatchDownloadQuality { library.effectiveQuality }

    /// Nobody has picked a quality yet, so the first add asks.
    var needsQualityChoice: Bool { library.quality == nil }

    /// A watch is paired and has Cue on it, so music can be put there.
    var isAvailable: Bool { isPaired && isWatchAppInstalled }

    @ObservationIgnored private let logger = Logger(subsystem: "dance.cue", category: "WatchSync")
    /// The session's delegate, kept alive here; nil where there's no
    /// WatchConnectivity.
    @ObservationIgnored private var relay: AnyObject?
    /// The sign-ins last sent, so signing in or out, or a new server, goes
    /// across too.
    @ObservationIgnored private var sentCredentials: WatchCredentials?
    @ObservationIgnored private var foregroundObserver: NSObjectProtocol?

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
        // Sign-ins change in Settings; coming back to Cue is when to check.
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sendIfCredentialsChanged() }
        }
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
        guard let source = WatchSource(item.content.service) else { return false }
        if item.content.type == .track {
            let key = WatchKeys.track(source: source, id: item.content.id)
            return library.collection(key: WatchCollection.songsKey)?.trackKeys.contains(key) == true
        }
        return library.collection(key: Self.collectionKey(for: item, source: source)) != nil
    }

    func isAdding(_ item: PlayableContent) -> Bool {
        guard let source = WatchSource(item.content.service) else { return false }
        return addingKeys.contains(Self.collectionKey(for: item, source: source))
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
    /// what's already there refreshes it: a playlist picks up its new songs.
    /// Returns how many songs it put there; 0 means nothing could go.
    @discardableResult
    func add(_ item: PlayableContent) async -> Int {
        guard canAdd(item), let source = WatchSource(item.content.service) else { return 0 }
        let quality = effectiveQuality
        if item.content.type == .track {
            guard let track = Self.watchTrack(for: item, quality: quality) else { return 0 }
            library.addSongs([track], at: .now)
            libraryDidChange()
            return 1
        }

        let key = Self.collectionKey(for: item, source: source)
        guard !addingKeys.contains(key) else { return 0 }
        addingKeys.insert(key)
        defer { addingKeys.remove(key) }

        let fetched = await LocalPlaybackService.shared.allContainerTracks(for: item)
        var seen = Set<String>()
        let tracks = fetched.compactMap { Self.watchTrack(for: $0, quality: quality) }.filter { seen.insert($0.key).inserted }
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
        guard let source = WatchSource(item.content.service) else { return }
        if item.content.type == .track {
            library.removeSong(key: WatchKeys.track(source: source, id: item.content.id))
        } else {
            library.removeCollection(key: Self.collectionKey(for: item, source: source))
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
    /// until the new one lands; a song with no origin (put there before
    /// origins were kept) stays as it is until it's added again.
    func setQuality(_ quality: WatchDownloadQuality) {
        guard quality != library.quality else { return }
        library.quality = quality
        for (key, track) in library.tracks {
            library.tracks[key] = track.converted(to: quality)
        }
        libraryDidChange()
    }

    private func libraryDidChange() {
        library.bumpRevision()
        saveLibrary()
        send()
    }

    /// A newer library from the watch — it added or removed something
    /// itself — taken as it is. Not sent back: the watch has it.
    private func adopt(_ newer: WatchLibrary) {
        guard newer.revision > library.revision else { return }
        library = newer
        saveLibrary()
        logger.info("Took the watch's library, revision \(newer.revision), \(newer.tracks.count) songs")
    }

    // MARK: - Building songs

    /// A Plex or Subsonic song as the watch fetches it at `quality`: its
    /// origin kept, so either device can build its stream again.
    static func watchTrack(for item: PlayableContent, quality: WatchDownloadQuality) -> WatchTrack? {
        guard DownloadManager.shared.canDownload(item),
              let source = WatchSource(item.content.service),
              let sourceURL = item.previewURL else { return nil }
        let origin = WatchTrackOrigin(source: source, contentID: item.content.id, sourceURL: sourceURL, audioCodec: item.metadata?.audioCodec)
        let track = WatchTrack(
            key: WatchKeys.track(source: source, id: item.content.id),
            title: item.title,
            artist: item.metadata?.artist ?? item.subtitle,
            album: item.metadata?.album,
            artworkURL: item.thumbnail ?? item.artwork,
            streamURL: sourceURL,
            fileExtension: item.metadata?.audioCodec ?? "mp3",
            duration: item.metadata?.duration.map { Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18 },
            origin: origin
        )
        return track.converted(to: quality)
    }

    static func collectionKey(for item: PlayableContent, source: WatchSource) -> String {
        WatchKeys.collection(kind: WatchCollection.Kind(item.content.type), source: source, id: item.content.id)
    }

    // MARK: - Sign-ins

    /// This iPhone's Plex and Subsonic sign-ins, as MusicSearchKit keeps them.
    private func currentCredentials() -> WatchCredentials {
        var credentials = WatchCredentials()
        if let token = PlexAuthenticator.shared.authToken, !token.isEmpty {
            let plex = PlexAPI.shared
            credentials.plex = .init(
                token: token,
                serverID: plex.serverID,
                librarySectionID: plex.librarySelectionID,
                connectionPreference: plex.connectionPreference.rawValue
            )
        }
        let subsonic = SubsonicAPI.shared
        if subsonic.isConfigured {
            credentials.subsonic = .init(serverAddress: subsonic.serverAddress, username: subsonic.username, password: subsonic.password)
        }
        return credentials
    }

    private func sendIfCredentialsChanged() {
        guard isAvailable, currentCredentials() != sentCredentials else { return }
        send()
    }

    // MARK: - Session

    /// Sends the library and the sign-ins as application context — or, when
    /// the library is too big for it, the sign-ins there and the library as
    /// a file, in place of any older copy still waiting to go. File transfers
    /// never arrive between simulators, so context is the way that works
    /// everywhere; a file stays until its transfer finishes (the system
    /// reads it as it goes).
    private func send() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let session = WCSession.default
        guard session.activationState == .activated, isAvailable else { return }
        for transfer in session.outstandingFileTransfers where WatchSyncMessage.isLibrary(transfer.file.metadata) {
            transfer.cancel()
        }
        Self.clearOutgoing()
        let credentials = currentCredentials()
        let libraryFits: Bool
        do {
            let (context, fits) = try WatchSyncMessage.context(library: library, credentials: credentials)
            try session.updateApplicationContext(context)
            sentCredentials = credentials
            libraryFits = fits
            logger.info("Sent the watch library, revision \(self.library.revision), \(self.library.tracks.count) songs, \(fits ? "in context" : "as a file")")
        } catch {
            logger.error("Couldn't send the watch context: \(error.localizedDescription, privacy: .public)")
            libraryFits = false
        }
        guard !libraryFits else { return }
        let url = Self.outgoingDirectory.appendingPathComponent("library-\(library.revision).json")
        do {
            try FileManager.default.createDirectory(at: Self.outgoingDirectory, withIntermediateDirectories: true)
            try library.encoded().write(to: url, options: .atomic)
        } catch {
            logger.error("Couldn't write the watch library: \(error.localizedDescription, privacy: .public)")
            return
        }
        session.transferFile(url, metadata: WatchSyncMessage.libraryMetadata(revision: library.revision))
        #endif
    }

    /// Sends the library when the watch is behind it and no copy is on its
    /// way: after a reinstall, a first pairing, or a transfer that failed.
    /// A watch ahead of it sends its own, which `adopt` takes.
    private func sendIfWatchIsBehind() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let session = WCSession.default
        guard session.activationState == .activated, isAvailable else { return }
        if currentCredentials() != sentCredentials {
            send()
            return
        }
        // Nothing to send to a watch that has nothing and should have nothing.
        let watchRevision = status?.libraryRevision ?? 0
        guard library.revision > 0, watchRevision < library.revision else { return }
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

    /// The watch's context: its library first, when newer, then its status.
    fileprivate func didReceive(library newer: WatchLibrary?, status: WatchStatus?) {
        if let newer {
            adopt(newer)
        }
        if let status {
            self.status = status
            Self.saveStatus(status)
        }
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
        let context = session.receivedApplicationContext
        let library = WatchSyncMessage.library(in: context)
        let status = WatchSyncMessage.status(in: context)
        Task { @MainActor in
            self.service?.didReceive(library: library, status: status)
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
        let library = WatchSyncMessage.library(in: applicationContext)
        let status = WatchSyncMessage.status(in: applicationContext)
        Task { @MainActor in
            self.service?.didReceive(library: library, status: status)
        }
    }

    /// A library from the watch too big for its context.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard WatchSyncMessage.isLibrary(file.metadata) else { return }
        // Read now: the system deletes the file when this returns.
        guard let data = try? Data(contentsOf: file.fileURL),
              let library = try? WatchLibrary.decoded(from: data) else { return }
        Task { @MainActor in
            self.service?.didReceive(library: library, status: nil)
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
    /// This song's stream at `quality`, built from its origin the way the
    /// watch builds it (`ConvertedStream`). One with no origin stays as it is.
    func converted(to quality: WatchDownloadQuality) -> WatchTrack {
        guard let origin, let service = ConvertedStream.Service(rawValue: origin.source.rawValue) else { return self }
        let stream = ConvertedStream.stream(
            service: service,
            contentID: origin.contentID,
            sourceURL: origin.sourceURL,
            audioCodec: origin.audioCodec,
            format: quality.bitrate == nil ? .original : .mp3,
            bitrate: quality.bitrate ?? StreamTranscoding.defaultBitrate
        )
        return withStream(stream.url, fileExtension: stream.fileExtension, quality: quality)
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

extension WatchSource {
    init?(_ service: MusicService) {
        switch service {
        case .plex: self = .plex
        case .subsonic: self = .subsonic
        default: return nil
        }
    }
}
