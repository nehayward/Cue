import Defaults
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

/// Tells the Apple Watch what to put on itself, and how to reach it.
///
/// The watch is the client: it browses Plex and Subsonic itself, and the
/// books on Plex and Audiobookshelf, looks songs and books up and downloads
/// them (MusicSearchKit). All this iPhone sends is a list of picks —
/// albums, playlists, artists, songs and books by id (`WatchPicks`) — the
/// places in the books among them (`WatchBookPlaces`, from
/// `AudiobookProgressStore`) and its sign-ins (`WatchCredentials`), as
/// application context. The watch changes the picks and places too, from
/// its own browsing and listening, and sends them back; each side merges
/// what the other sends (`WatchPicks.merged`, `WatchBookPlaces.merged`), so
/// neither loses the other's changes, and a book picks up on either device
/// where it was left on the other.
///
/// Audiobookshelf's sign-in is lent: the access token, never the refresh
/// token, which the server rotates on every renewal. When the token the
/// watch holds is about to run out it asks for the next one
/// (`WatchSyncMessage.credentialsRequest`), and this iPhone renews its own
/// to answer.
///
/// Only Plex, Subsonic and Audiobookshelf, as with the download manager:
/// their files are plain URLs the watch can fetch. Apple Music on the watch
/// is the Music app's (MusicKit has no player on watchOS).
///
/// Inert where there's no watch to pair (iPad, Mac, Vision Pro): nothing
/// is available, so no menu offers it.
@MainActor
@Observable
final class WatchSyncService {
    static let shared = WatchSyncService()

    private(set) var picks: WatchPicks
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false

    /// A watch is paired and has Cue on it, so music can be put there.
    var isAvailable: Bool { isPaired && isWatchAppInstalled }

    @ObservationIgnored private let logger = Logger(subsystem: "dance.cue", category: "WatchSync")
    /// The session's delegate, kept alive here; nil where there's no
    /// WatchConnectivity.
    @ObservationIgnored private var relay: AnyObject?
    /// The sign-ins last sent, so signing in or out, or a new server, goes
    /// across too.
    @ObservationIgnored private var sentCredentials: WatchCredentials?
    /// The places last sent, so a book listened to here goes across.
    @ObservationIgnored private var sentPlaces: WatchBookPlaces?
    @ObservationIgnored private var placesTask: Task<Void, Never>?
    /// The watch's places taken in this launch, by pick: a place this
    /// iPhone holds only because the watch sent it isn't this iPhone's to
    /// keep in the book's history.
    @ObservationIgnored private var takenFromWatch: [String: AudiobookProgress] = [:]
    @ObservationIgnored private var backgroundObserver: NSObjectProtocol?
    @ObservationIgnored private var foregroundObserver: NSObjectProtocol?

    private init() {
        picks = (try? Data(contentsOf: Self.picksURL)).flatMap { try? WatchPicks.decoded(from: $0) } ?? .empty
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
            Task { @MainActor in
                guard let self, self.currentCredentials() != self.sentCredentials else { return }
                self.send()
            }
        }
        // Leaving Cue, a place a book reached here goes across at once.
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.currentPlaces() != self.sentPlaces else { return }
                self.send()
            }
        }
        #endif
    }

    // MARK: - Picks

    /// Whether this can go on the watch: a Plex or Subsonic song with its
    /// stream, an album, playlist or artist of them, or a Plex or
    /// Audiobookshelf book — what the download manager takes — and a watch
    /// with Cue to put it on.
    func canAdd(_ item: PlayableContent) -> Bool {
        guard isAvailable else { return false }
        let downloads = DownloadManager.shared
        return item.content.type == .track ? downloads.canDownload(item) : downloads.canDownload(contentsOf: item)
    }

    func isOnWatch(_ item: PlayableContent) -> Bool {
        Self.pick(for: item).map { picks.contains(key: $0.key) } ?? false
    }

    func add(_ item: PlayableContent) {
        guard canAdd(item), let pick = Self.pick(for: item) else { return }
        picks.add(pick)
        picksDidChange()
    }

    func remove(_ item: PlayableContent) {
        guard let pick = Self.pick(for: item) else { return }
        remove(key: pick.key)
    }

    func remove(key: String) {
        picks.remove(key: key)
        picksDidChange()
    }

    func removeAll() {
        picks.removeAll()
        picksDidChange()
    }

    private func picksDidChange() {
        save()
        send()
    }

    /// An album, playlist, artist, song or book as the watch looks it up:
    /// by the id this iPhone's library gives it.
    static func pick(for item: PlayableContent) -> WatchPick? {
        guard let source = WatchSource(item.content.service) else { return nil }
        let kind: WatchPick.Kind
        switch item.content.type {
        case .track: kind = .song
        case .album: kind = .album
        case .playlist: kind = .playlist
        case .artist: kind = .artist
        case .audiobook: kind = .audiobook
        default: return nil
        }
        return WatchPick(
            source: source,
            kind: kind,
            id: item.content.id,
            title: item.title,
            subtitle: item.metadata?.artist ?? item.subtitle,
            artworkURL: item.thumbnail ?? item.artwork
        )
    }

    // MARK: - Books

    /// The places in the books picked for the watch, as this iPhone has
    /// them (`AudiobookProgressStore`).
    private func currentPlaces() -> WatchBookPlaces {
        let store = AudiobookProgressStore.shared
        var places = WatchBookPlaces.empty
        for pick in picks.items where pick.kind == .audiobook {
            guard let reading = store.progress(for: Self.book(for: pick)) else { continue }
            places.record(WatchBookPlace(reading), for: pick.key)
        }
        return places
    }

    /// A book's place moved here (`AudiobookProgressStore.record`): the
    /// watch hears of it a minute after the first change, or as Cue leaves
    /// the screen, rather than every few seconds of listening.
    func bookPlacesDidChange() {
        guard isAvailable, picks.items.contains(where: { $0.kind == .audiobook }), placesTask == nil else { return }
        placesTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self else { return }
            self.placesTask = nil
            guard self.currentPlaces() != self.sentPlaces else { return }
            self.send()
        }
    }

    /// The watch's places in its books, kept where they're newer than this
    /// iPhone's: the book picks up here where it was left there, and its
    /// server hears of the place when the book next opens
    /// (`AudiobookLibrary.load`). This iPhone's own place stays in the
    /// book's history, and a book loaded here but paused gives way, so Play
    /// starts from the watch's place. Only for a server this iPhone is
    /// signed in to: a sign-out forgets that account's places, and the
    /// watch's mustn't bring them back.
    private func apply(_ theirs: WatchBookPlaces) {
        let store = AudiobookProgressStore.shared
        for pick in picks.items where pick.kind == .audiobook && Self.isSignedIn(to: pick.source) {
            guard let place = theirs[pick.key] else { continue }
            let book = Self.book(for: pick)
            let held = store.progress(for: book)
            if let held, !place.supersedes(WatchBookPlace(held)) { continue }
            let reading = AudiobookProgress(place)
            if let held, held != takenFromWatch[pick.key], !held.isFinished, held.position > 0, abs(held.position - reading.position) > 60 {
                AudiobookPlaceHistory.shared.record(.replaced, at: held.position, for: book)
            }
            logger.info("\(pick.title, privacy: .public): the watch's place, \(Int(reading.position)) s, is newer")
            takenFromWatch[pick.key] = reading
            store.record(reading, for: book)
            Task { await AudiobookPlayer.shared.notePlaceMoved(book, to: reading) }
        }
    }

    private static func isSignedIn(to source: WatchSource) -> Bool {
        switch source {
        case .plex: !(PlexAuthenticator.shared.authToken ?? "").isEmpty
        case .subsonic: SubsonicAPI.shared.isConfigured
        case .audiobookshelf: AudiobookshelfAPI.shared.isConfigured
        }
    }

    /// The book a pick names, as this iPhone's stores know it: by its server
    /// and id.
    private static func book(for pick: WatchPick) -> PlayableContent {
        PlayableContent(
            title: pick.title,
            subtitle: pick.subtitle,
            thumbnail: pick.artworkURL,
            artwork: pick.artworkURL,
            content: .init(service: pick.source.service, id: pick.id, type: .audiobook, location: nil)
        )
    }

    // MARK: - Session

    /// This iPhone's sign-ins, as MusicSearchKit keeps them: Plex's with
    /// which of its libraries hold books, Subsonic's, and Audiobookshelf's
    /// access token, lent.
    private func currentCredentials() -> WatchCredentials {
        var credentials = WatchCredentials()
        if let token = PlexAuthenticator.shared.authToken, !token.isEmpty {
            let plex = PlexAPI.shared
            credentials.plex = .init(
                token: token,
                serverID: plex.serverID,
                librarySectionID: plex.librarySelectionID,
                connectionPreference: plex.connectionPreference.rawValue,
                hasBooks: UserDefaults.standard.bool(forKey: AppStorageKeys.hasPlexAudiobooks),
                bookLibraryKeys: plex.chosenAudiobookLibraryKeys,
                includesGenreTaggedBooks: plex.includesGenreTaggedAudiobooks
            )
        }
        let subsonic = SubsonicAPI.shared
        if subsonic.isConfigured {
            credentials.subsonic = .init(serverAddress: subsonic.serverAddress, username: subsonic.username, password: subsonic.password)
        }
        let shelf = AudiobookshelfAPI.shared
        if shelf.isConfigured, let token = AudiobookshelfAPI.currentAccessToken {
            credentials.audiobookshelf = .init(serverAddress: shelf.serverAddress, username: shelf.username, accessToken: token)
        }
        return credentials
    }

    /// How long the token lent to the watch has to last: it asks for one
    /// ten minutes before its own runs out, so this covers that and more.
    private static let lentTokenLife: TimeInterval = 20 * 60

    /// The sign-ins for the watch's request: Audiobookshelf's token renewed
    /// first when it runs out soon, and the context sent again with it, so
    /// the watch reading that again later finds the new one.
    fileprivate func credentialsForWatch() async -> WatchCredentials {
        if AudiobookshelfAPI.shared.isConfigured, AudiobookshelfAPI.accessTokenExpires(within: Self.lentTokenLife) {
            _ = await AudiobookshelfAPI.shared.renewAccessToken()
        }
        let credentials = currentCredentials()
        if credentials != sentCredentials {
            send()
        }
        return credentials
    }

    /// The picks, the places in the books among them and the sign-ins, as
    /// application context: only the latest matters, and it reaches a watch
    /// app that isn't running.
    private func send() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard WCSession.default.activationState == .activated, isAvailable else { return }
        let credentials = currentCredentials()
        let places = currentPlaces()
        do {
            try WCSession.default.updateApplicationContext(WatchSyncMessage.context(picks: picks, places: places, credentials: credentials))
            sentCredentials = credentials
            sentPlaces = places
        } catch {
            logger.error("Couldn't send to the watch: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    fileprivate func sessionStateDidChange(isPaired: Bool, isWatchAppInstalled: Bool) {
        self.isPaired = isPaired
        self.isWatchAppInstalled = isWatchAppInstalled
        // A watch newly paired or with Cue newly on it hasn't heard yet.
        send()
    }

    /// The watch's picks and places, merged in. When the watch was missing
    /// something of ours — a pick, or a place it hasn't or that's newer —
    /// it hears back.
    fileprivate func didReceive(picks theirs: WatchPicks?, places theirPlaces: WatchBookPlaces?) {
        var tellWatch = false
        if let theirs {
            let merged = picks.merged(with: theirs)
            if merged != picks {
                picks = merged
                save()
            }
            tellWatch = merged != theirs
        }
        if let theirPlaces {
            apply(theirPlaces)
            let ours = currentPlaces()
            if ours.hasNews(for: theirPlaces) {
                tellWatch = true
            } else {
                // The watch has every place this iPhone does: nothing to
                // send it when the ones just taken in note their change.
                sentPlaces = ours
            }
        }
        if tellWatch {
            send()
        }
    }

    // MARK: - Storage

    private static var picksURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("AppleWatch/picks.json")
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.picksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try picks.encoded().write(to: Self.picksURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            logger.error("Couldn't save the watch picks: \(error.localizedDescription, privacy: .public)")
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
        let picks = WatchSyncMessage.picks(in: session.receivedApplicationContext)
        let places = WatchSyncMessage.places(in: session.receivedApplicationContext)
        Task { @MainActor in
            if picks != nil || places != nil {
                self.service?.didReceive(picks: picks, places: places)
            }
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
        let picks = WatchSyncMessage.picks(in: applicationContext)
        let places = WatchSyncMessage.places(in: applicationContext)
        guard picks != nil || places != nil else { return }
        Task { @MainActor in
            self.service?.didReceive(picks: picks, places: places)
        }
    }

    /// The watch asking for the sign-ins afresh: its Audiobookshelf token is
    /// about to run out. The system wakes Cue to answer.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard WatchSyncMessage.isCredentialsRequest(message) else {
            replyHandler([:])
            return
        }
        let reply = UncheckedReply(send: replyHandler)
        Task { @MainActor in
            guard let service = self.service else {
                reply.send([:])
                return
            }
            let credentials = await service.credentialsForWatch()
            reply.send((try? WatchSyncMessage.credentialsReply(credentials)) ?? [:])
        }
    }
}

/// WatchConnectivity's reply handler, carried to the main actor and called
/// once from there.
private struct UncheckedReply: @unchecked Sendable {
    let send: ([String: Any]) -> Void
}
#endif

extension WatchSource {
    init?(_ service: MusicService) {
        switch service {
        case .plex: self = .plex
        case .subsonic: self = .subsonic
        case .audiobookshelf: self = .audiobookshelf
        default: return nil
        }
    }

    var service: MusicService {
        switch self {
        case .plex: .plex
        case .subsonic: .subsonic
        case .audiobookshelf: .audiobookshelf
        }
    }
}

extension WatchBookPlace {
    init(_ progress: AudiobookProgress) {
        self.init(position: progress.position, duration: progress.duration, isFinished: progress.isFinished, updatedAt: progress.updatedAt)
    }
}

extension AudiobookProgress {
    init(_ place: WatchBookPlace) {
        self.init(position: place.position, duration: place.duration, isFinished: place.isFinished, updatedAt: place.updatedAt)
    }
}
