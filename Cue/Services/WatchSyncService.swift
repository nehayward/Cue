import Defaults
import Foundation
import MusicSearchKit
import Observation
import OSLog
import SonosKit
import WatchSync
#if os(iOS) && !targetEnvironment(macCatalyst)
import Nuke
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
/// where it was left on the other. The places also go through iCloud's
/// key-value store (`CloudBookPlaces`), read at launch, on coming back to
/// Cue and whenever it changes, so they cross with the watch out of reach.
///
/// Audiobookshelf's sign-in is lent: the access token, never the refresh
/// token, which the server rotates on every renewal. When the token the
/// watch holds is about to run out it asks for the next one
/// (`WatchSyncMessage.credentialsRequest`), and this iPhone renews its own
/// to answer.
///
/// While the watch app is open (reachable) the watch also hears what this
/// iPhone plays — `PlaybackRoute.presented`, here or on a Sonos group — as
/// it changes, for its home screen's card, and plays, pauses and skips it
/// from its player of it (`WatchPhoneNowPlaying`), whose Up Next asks for
/// the queue it plays from and plays a song in it (`WatchPhoneQueue`).
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

    /// What the watch said it holds against the free songs, which the two
    /// share (`WatchAllowance`).
    private(set) var watchHeld: WatchHeldDownloads?

    /// The watch's songs and books, as counted against the free songs. None
    /// for a watch that's gone, which takes its downloads with it.
    var heldOnWatch: Int {
        isAvailable ? watchHeld?.total ?? 0 : 0
    }

    @ObservationIgnored private let logger = Logger(subsystem: "dance.cue", category: "WatchSync")
    /// The session's delegate, kept alive here; nil where there's no
    /// WatchConnectivity.
    @ObservationIgnored private var relay: AnyObject?
    /// The sign-ins last sent, so signing in or out, or a new server, goes
    /// across too.
    @ObservationIgnored private var sentCredentials: WatchCredentials?
    /// The places last sent, so a book listened to here goes across.
    @ObservationIgnored private var sentPlaces: WatchBookPlaces?
    @ObservationIgnored private var sentAllowance: WatchAllowance?
    @ObservationIgnored private var placesTask: Task<Void, Never>?
    @ObservationIgnored private let cloud = CloudBookPlaces()
    @ObservationIgnored private var cloudObserver: NSObjectProtocol?
    /// The watch's places taken in this launch, by pick: a place this
    /// iPhone holds only because the watch sent it isn't this iPhone's to
    /// keep in the book's history.
    @ObservationIgnored private var takenFromWatch: [String: AudiobookProgress] = [:]
    @ObservationIgnored private var backgroundObserver: NSObjectProtocol?
    @ObservationIgnored private var foregroundObserver: NSObjectProtocol?
    #if os(iOS) && !targetEnvironment(macCatalyst)
    /// The watch app is open and in reach: what plays here goes across as
    /// it changes.
    @ObservationIgnored private var isWatchReachable = false
    /// An observation of what plays is armed; one at a time.
    @ObservationIgnored private var isTrackingNowPlaying = false
    /// What the watch last heard plays here.
    @ObservationIgnored private var sentNowPlaying: NowPlayingState?
    @ObservationIgnored private var nowPlayingTask: Task<Void, Never>?
    /// What plays here as the application context carries it, for the watch
    /// app to show the moment it opens, before it asks: without its cover,
    /// as the context also carries the picks and has a size limit. Nil
    /// until first read.
    @ObservationIgnored private var contextNowPlaying: Data?
    /// What `contextNowPlaying` was made from, short of the clock.
    @ObservationIgnored private var contextState: NowPlayingState?
    @ObservationIgnored private var contextTask: Task<Void, Never>?
    #endif

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
        // Sign-ins change in Settings; coming back to Cue is when to check,
        // and to read the places iCloud brought while Cue was away.
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reconcileWithCloud()
                guard self.currentCredentials() != self.sentCredentials else { return }
                self.send()
            }
        }
        // Leaving Cue, a place a book reached here goes across at once.
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.sharePlaces()
            }
        }
        cloudObserver = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: NSUbiquitousKeyValueStore.default, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.reconcileWithCloud()
            }
        }
        NSUbiquitousKeyValueStore.default.synchronize()
        reconcileWithCloud()
        trackAllowance()
        #endif
    }

    // MARK: - The free tier's share

    /// The watch's share of the free downloads: the free songs this iPhone
    /// doesn't hold, none of a limit with Super; books only with Super.
    private func currentAllowance() -> WatchAllowance {
        let gate = FeatureGate.shared
        let songs = gate.isAvailable(.unlimitedDownloads) ? nil : max(0, DownloadManager.freeSongLimit - DownloadManager.shared.heldCount)
        return WatchAllowance(songs: songs, allowsBooks: gate.isAvailable(.bookDownloads))
    }

    /// Tells the watch when its share changes: Super coming or going, or a
    /// download here taking or freeing a slot. One observation at a time,
    /// each change arming the next a second later: progress rewrites the
    /// downloads several times a second, and a batch queued or removed
    /// goes as one.
    private func trackAllowance() {
        let allowance = withObservationTracking {
            currentAllowance()
        } onChange: { [weak self] in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                self?.trackAllowance()
            }
        }
        if allowance != sentAllowance {
            send()
        }
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
    /// watch and iCloud hear of it a minute after the first change, or as
    /// Cue leaves the screen, rather than every few seconds of listening.
    func bookPlacesDidChange() {
        guard isAvailable, picks.items.contains(where: { $0.kind == .audiobook }), placesTask == nil else { return }
        placesTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self else { return }
            self.placesTask = nil
            self.sharePlaces()
        }
    }

    /// The places go up to iCloud where they're newer than its, and to the
    /// watch when they've changed since it last heard.
    private func sharePlaces() {
        placesTask?.cancel()
        placesTask = nil
        let places = currentPlaces()
        let written = cloud.write(places)
        if !written.isEmpty {
            logger.info("Put \(written.count) book places in iCloud")
        }
        guard places != sentPlaces else { return }
        send()
    }

    /// iCloud's places in, where they're newer than this iPhone's — the
    /// watch's, from when it was out of reach — and this iPhone's up, where
    /// they're newer than iCloud's: what was there may have been an older
    /// place that reached iCloud last.
    private func reconcileWithCloud() {
        apply(cloud.read(), from: "iCloud")
        let written = cloud.write(currentPlaces())
        if !written.isEmpty {
            logger.info("Put \(written.count) book places in iCloud")
        }
    }

    /// The watch's places in its books, kept where they're newer than this
    /// iPhone's: the book picks up here where it was left there, and its
    /// server hears of the place when the book next opens
    /// (`AudiobookLibrary.load`). This iPhone's own place stays in the
    /// book's history, and a book loaded here but paused gives way, so Play
    /// starts from the watch's place. Only for a server this iPhone is
    /// signed in to: a sign-out forgets that account's places, and the
    /// watch's mustn't bring them back. The same for iCloud's, which are
    /// the watch's, or this iPhone's own coming back.
    private func apply(_ theirs: WatchBookPlaces, from source: String = "the watch") {
        for pick in picks.items where pick.kind == .audiobook && Self.isSignedIn(to: pick.source) {
            guard let place = theirs[pick.key] else { continue }
            take(place, for: pick, from: source)
        }
    }

    /// One book's place from the watch (or iCloud), kept where it's newer
    /// than this iPhone's; the book loaded here gives way to it, unless the
    /// caller does that itself (`movesPlayer`). The place taken, if it was.
    @discardableResult
    private func take(_ place: WatchBookPlace, for pick: WatchPick, from source: String, movesPlayer: Bool = true) -> AudiobookProgress? {
        let store = AudiobookProgressStore.shared
        let book = Self.book(for: pick)
        let held = store.progress(for: book)
        if let held, !place.supersedes(WatchBookPlace(held)) { return nil }
        let reading = AudiobookProgress(place)
        if let held, held != takenFromWatch[pick.key], !held.isFinished, held.position > 0, abs(held.position - reading.position) > 60 {
            AudiobookPlaceHistory.shared.record(.replaced, at: held.position, to: reading.position, for: book, from: .watch)
        }
        logger.info("\(pick.title, privacy: .public): the place from \(source, privacy: .public), \(Int(reading.position)) s, is newer")
        takenFromWatch[pick.key] = reading
        store.record(reading, for: book)
        if movesPlayer {
            Task { await AudiobookPlayer.shared.notePlaceMoved(book, to: reading) }
        }
        return reading
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
        let allowance = currentAllowance()
        do {
            try WCSession.default.updateApplicationContext(WatchSyncMessage.context(picks: picks, places: places, credentials: credentials, allowance: allowance, nowPlaying: contextNowPlaying))
            sentCredentials = credentials
            sentPlaces = places
            sentAllowance = allowance
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
        #if os(iOS) && !targetEnvironment(macCatalyst)
        trackNowPlaying()
        #endif
    }

    /// The watch's picks and places, merged in. When the watch was missing
    /// something of ours — a pick, or a place it hasn't or that's newer —
    /// it hears back.
    fileprivate func didReceive(picks theirs: WatchPicks?, places theirPlaces: WatchBookPlaces?, held: WatchHeldDownloads? = nil) {
        if let held, held != watchHeld {
            watchHeld = held
        }
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

    // MARK: - Now Playing

    #if os(iOS) && !targetEnvironment(macCatalyst)
    /// What the watch's card and player show of the playback here, short of
    /// the cover itself and the clock: a change to any of it goes across.
    private struct NowPlayingState: Equatable {
        var title: String
        var artist: String?
        var destination: String
        var isOnSpeaker: Bool
        var isPlaying: Bool
        var isBook: Bool
        var canGoBack: Bool
        var hasNext: Bool
        var queuePosition: Int
        var queueCount: Int
        var artworkURL: URL?
        var duration: TimeInterval?
        var rate: Double
        var chapter: String?
        var chapterID: Int?
        var chapterStart: TimeInterval?
        var bookKey: String?
        var sleepsAt: Date?
        var sleepsAtEnd: Bool
    }

    /// Where the song (or a book's chapter) was, and when: the watch runs
    /// its own clock on from it.
    private struct Clock {
        var elapsed: TimeInterval?
        var at: Date
        var rate: Double
        var isPlaying: Bool

        /// Where this clock says it is at `date`.
        func elapsed(at date: Date) -> TimeInterval? {
            elapsed.map { $0 + (isPlaying ? date.timeIntervalSince(at) * rate : 0) }
        }
    }

    private typealias NowPlaying = (state: NowPlayingState, clock: Clock, item: PlayableContent)

    /// What the player shows, here or on a speaker: a book as itself, by
    /// its author, as the watch's own card has it, with the player's skips
    /// (a book's 15 and 30 s), the chapter playing and the time into it
    /// against its length (the book's, without chapters), at the book's
    /// speed here (a speaker plays at 1×); a song's time against its length.
    private func currentNowPlaying() -> NowPlaying? {
        let controller = PlaybackRoute.shared.presented
        guard let item = controller.nowPlayingDisplay else { return nil }
        let books = AudiobookPlayer.shared
        let sleepsAtChapterEnd = books.sleepsAt != nil
        var state = NowPlayingState(
            title: item.title,
            artist: item.metadata?.artist ?? item.subtitle,
            destination: controller.name,
            isOnSpeaker: controller.group != nil,
            isPlaying: controller.isPlaying,
            isBook: false,
            canGoBack: controller.showsPrevious && controller.canGoBack,
            hasNext: controller.showsNext && controller.hasNext,
            queuePosition: controller.queuePosition,
            queueCount: controller.queueCount,
            artworkURL: item.artwork ?? item.thumbnail,
            duration: controller.duration > 0 ? controller.duration : nil,
            rate: 1,
            sleepsAt: controller.sleepTimerEndDate.flatMap { $0 > .now ? $0 : nil },
            sleepsAtEnd: controller.sleepsAtEndOfTrack
        )
        var clock = Clock(elapsed: state.duration == nil ? nil : controller.position(), at: .now, rate: 1, isPlaying: state.isPlaying)
        if let book = books.current, let part = book.partIndex(of: item) {
            state.title = book.book.title
            state.artist = book.book.subtitle
            state.artworkURL = book.book.artwork ?? state.artworkURL
            state.isBook = true
            state.canGoBack = true
            state.hasNext = true
            state.bookKey = Self.pick(for: book.book)?.key
            state.rate = controller.group == nil ? books.rate : 1
            state.sleepsAtEnd = sleepsAtChapterEnd
            // Read for its change, which a new chapter is (within the
            // follow's couple of seconds): the clock alone doesn't change
            // as a chapter ends.
            _ = books.currentChapter
            let time = book.time(part: part, offset: controller.position())
            if books.hasChapters, let chapter = book.chapter(at: time) {
                state.chapter = chapter.title
                state.chapterID = chapter.id
                state.chapterStart = chapter.start
                state.duration = chapter.duration
                clock.elapsed = min(max(time - chapter.start, 0), chapter.duration)
            } else {
                state.duration = book.duration
                clock.elapsed = time
            }
            clock.rate = state.rate
        }
        return (state, clock, item)
    }

    /// The clock the watch last heard.
    @ObservationIgnored private var sentClock: Clock?

    /// The watch's clock has drifted from this one, or it was moved: worth
    /// sending again though nothing else changed.
    private func clockMoved(_ clock: Clock) -> Bool {
        guard let sentClock else { return true }
        guard let now = clock.elapsed(at: .now), let heard = sentClock.elapsed(at: .now) else {
            return (clock.elapsed == nil) != (sentClock.elapsed == nil)
        }
        return abs(now - heard) > 2
    }

    fileprivate func reachabilityDidChange(_ isReachable: Bool) {
        isWatchReachable = isReachable
        if isReachable {
            // The watch app just opened: it hears afresh.
            sentNowPlaying = nil
            sentClock = nil
            trackNowPlaying()
        } else {
            nowPlayingTask?.cancel()
        }
    }

    /// Sends what plays when it changes: at once while the watch app is open,
    /// and into the context whatever the watch is doing, for the app to find
    /// as it opens. One observation at a time: each change arms the next.
    private func trackNowPlaying() {
        guard isAvailable || isWatchReachable, !isTrackingNowPlaying else { return }
        isTrackingNowPlaying = true
        let now = withObservationTracking {
            currentNowPlaying()
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isTrackingNowPlaying = false
                self.trackNowPlaying()
            }
        }
        if now?.state != contextState {
            updateContext()
        }
        guard isWatchReachable, now?.state != sentNowPlaying || now.map({ clockMoved($0.clock) }) == true else { return }
        sentNowPlaying = now?.state
        sentClock = now?.clock
        nowPlayingTask?.cancel()
        nowPlayingTask = Task { [weak self] in
            // A burst (a skip, a load and its buffering) goes as one.
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            // Read again: the clock has run on through the wait.
            let latest = self.currentNowPlaying()
            let message = await self.nowPlayingMessage(latest ?? now)
            guard !Task.isCancelled, WCSession.default.isReachable else { return }
            WCSession.default.sendMessage(message, replyHandler: nil) { [logger] error in
                logger.error("Couldn't tell the watch what's playing: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Puts what plays into the context once it has settled (a skip, a load
    /// and its buffering are a burst of changes): a song, a pause or a
    /// chapter, not the clock, which the watch runs on from when it was read.
    private func updateContext() {
        contextState = currentNowPlaying()?.state
        contextTask?.cancel()
        contextTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            let card = self.currentNowPlaying().map { self.watchNowPlaying($0, artwork: nil) }
            self.contextNowPlaying = try? WatchSyncMessage.nowPlayingCard(card)
            self.send()
        }
    }

    /// The watch asking what plays, or to play, pause or skip it as the
    /// player's own buttons do (a book skips back 15 s and ahead 30 s), to
    /// play a song in the queue or a chapter, to set the sleep timer or a
    /// book's speed, or to play one of its books here: answered with what
    /// plays then, the play state as it's been asked to be (a speaker says
    /// so a moment later; if it doesn't, the watch hears what it does say).
    fileprivate func answer(_ ask: WatchAsk) async -> [String: Any] {
        isWatchReachable = WCSession.default.isReachable
        trackNowPlaying()
        var playing: Bool?
        switch ask {
        case .nowPlaying:
            break
        case let .command(command):
            playing = await perform(command)
        case let .playQueue(position):
            await playFromQueue(at: position)
        case let .playChapter(id):
            await playChapter(id)
        case let .sleepTimer(sleep):
            await setSleepTimer(sleep)
        case let .speed(rate):
            if AudiobookPlayer.shared.current != nil {
                AudiobookPlayer.shared.setRate(rate)
            }
        case let .playBook(pick, place, time, target):
            await playBook(pick, place: place, from: time, on: target)
        case let .playItem(pick, songID, shuffled, target):
            await playItem(pick, from: songID, shuffled: shuffled, on: target)
        case let .switchRoute(id):
            switchRoute(to: id)
        }
        var now = currentNowPlaying()
        if let playing {
            now?.state.isPlaying = playing
            now?.clock.isPlaying = playing
        }
        sentNowPlaying = now?.state
        sentClock = now?.clock
        return await nowPlayingMessage(now)
    }

    /// A press on the watch's player of this one. For play and pause, the
    /// play state it asked for.
    private func perform(_ command: WatchPhoneCommand) async -> Bool? {
        let controller = PlaybackRoute.shared.presented
        let books = AudiobookPlayer.shared
        switch command {
        case .togglePlayPause:
            let wasPlaying = controller.isPlaying
            await controller.togglePlayback()
            return !wasPlaying
        case .previous:
            if books.isPlayingBook(on: controller) {
                await books.skip(by: -AudiobookPlayer.skipBackInterval)
            } else if controller.showsPrevious, controller.canGoBack {
                await controller.previous()
            }
        case .next:
            if books.isPlayingBook(on: controller) {
                await books.skip(by: AudiobookPlayer.skipForwardInterval)
            } else if controller.showsNext, controller.hasNext {
                await controller.next()
            }
        }
        return nil
    }

    /// The watch's Up Next playing a song in the queue, as a tap on a row of
    /// the player's own does: here from this iPhone's queue (a station in
    /// front of it put away), on a speaker from its queue (`seek(trackNumber:)`
    /// points it back at the queue from radio or TV). Not through a
    /// hand-off: the rows are the source's, on their way out.
    private func playFromQueue(at position: Int) async {
        let route = PlaybackRoute.shared
        guard !route.isHolding else { return }
        if let group = route.presentedGroup {
            await SonosService.shared.seek(trackNumber: position, on: group)
        } else {
            LocalPlaybackService.shared.play(at: position - 1)
        }
    }

    /// The watch's chapters of the book playing here, a tap on one: from
    /// its start, as the Chapters sheet plays it.
    private func playChapter(_ id: Int) async {
        let books = AudiobookPlayer.shared
        guard !PlaybackRoute.shared.isHolding, let book = books.current,
              books.isPlayingBook(on: PlaybackRoute.shared.presented),
              let chapter = book.chapters.first(where: { $0.id == id }) else { return }
        await books.play(chapter: chapter)
    }

    /// The watch's sleep timer for what plays here, as the player's menu
    /// sets one: End of Chapter for a book, End of Song for anything else,
    /// on the speaker for a group. Any other choice puts End of Chapter
    /// away, or it would move the new timer back to the chapter's end.
    private func setSleepTimer(_ sleep: WatchPhoneSleep) async {
        let route = PlaybackRoute.shared
        guard !route.isHolding else { return }
        let controller = route.presented
        let books = AudiobookPlayer.shared
        let sonos = SonosService.shared
        switch sleep {
        case .off:
            books.forgetChapterSleep()
            await controller.cancelSleepTimer()
        case .end:
            if books.isPlayingBook(on: controller) {
                await books.sleepAtEndOfChapter()
            } else if let group = controller.group {
                books.forgetChapterSleep()
                _ = await sonos.sleepAtEndOfTrack(group: group)
            } else {
                books.forgetChapterSleep()
                LocalPlaybackService.shared.sleepAtEndOfTrack()
            }
        case let .minutes(minutes):
            books.forgetChapterSleep()
            let duration = Duration.seconds(minutes * 60)
            if let group = controller.group {
                await sonos.sleepTimer(group: group, duration: duration)
            } else {
                LocalPlaybackService.shared.sleepTimer(duration)
            }
        }
    }

    /// One of the watch's books, to play here, from `time` or its place:
    /// the watch's when it's newer than this iPhone's, which the watch sends
    /// along rather than wait for its context to arrive. The book loaded and
    /// on the player where it's asked for plays on; any other is read from
    /// its server and started — on this iPhone itself (the route coming back
    /// here, as for a book in the Files folder), on a speaker (the route
    /// going there), or where the route goes.
    private func playBook(_ pick: WatchPick, place: WatchBookPlace?, from time: TimeInterval?, on target: WatchPhoneTarget) async {
        guard pick.kind == .audiobook, Self.isSignedIn(to: pick.source) else { return }
        let book = Self.book(for: pick)
        let route = PlaybackRoute.shared
        let books = AudiobookPlayer.shared
        // Moved there before Play, so Play starts from it.
        if let place, let reading = take(place, for: pick, from: "the watch", movesPlayer: false) {
            await books.notePlaceMoved(book, to: reading)
        }
        logger.info("The watch asks to play \(pick.title, privacy: .public) on \(target.key, privacy: .public)")
        if books.isLoaded(book), Self.isOn(target, route.presented) {
            if let time {
                await books.playLoaded(from: time)
            } else if !route.presented.isPlaying {
                await route.presented.togglePlayback()
            }
            return
        }
        guard moveRoute(to: target) else { return }
        await books.play(book, from: time, on: target == .iPhone ? .device : .route)
    }

    /// An album, playlist, artist or song from the watch's library, to play
    /// here: read from its server as the watch reads it, from the song
    /// `songID` in it or shuffled, on this iPhone, a speaker or where the
    /// route goes — the whole list in the queue, in place of what was there.
    private func playItem(_ pick: WatchPick, from songID: String?, shuffled: Bool, on target: WatchPhoneTarget) async {
        guard pick.kind != .audiobook, Self.isSignedIn(to: pick.source) else { return }
        logger.info("The watch asks to play \(pick.title, privacy: .public) on \(target.key, privacy: .public)")
        guard var songs = await Self.songs(for: pick), !songs.isEmpty else {
            logger.error("Couldn't read \(pick.title, privacy: .public) from its server for the watch")
            AlertService.shared.showAlert(with: "Couldn't open “\(pick.title)”", imageName: "exclamationmark.triangle")
            return
        }
        if shuffled {
            songs.shuffle()
        }
        var start = songID.flatMap { id in songs.firstIndex { $0.content.id == id } } ?? 0
        // Shuffled from a song: that one first.
        if shuffled, start > 0 {
            songs.swapAt(0, start)
            start = 0
        }
        guard moveRoute(to: target) else { return }
        do {
            if let group = PlaybackRoute.shared.group {
                // As a play on a speaker from here does: this device's
                // queue keeps its place for the route coming back.
                LocalPlaybackService.shared.park()
                try await SonosService.shared.queue(contents: songs, group: group, position: .replace, startIndex: start)
            } else {
                try await LocalPlaybackService.shared.play(songs, startingAt: start)
            }
        } catch {
            logger.error("Couldn't play \(pick.title, privacy: .public) for the watch: \(error.localizedDescription, privacy: .public)")
            AlertService.shared.showAlert(with: "Couldn't play “\(pick.title)”", imageName: "exclamationmark.triangle")
        }
    }

    /// Whether `controller` plays where `target` asks for.
    private static func isOn(_ target: WatchPhoneTarget, _ controller: any PlaybackController) -> Bool {
        switch target {
        case .route: true
        case .iPhone: controller.group == nil
        case let .group(id): controller.group?.coordinatorID == id
        }
    }

    /// Points the route at `target` before something plays there, carrying
    /// nothing: this iPhone, or a speaker it reaches and may play to. False
    /// for a speaker that's gone or is Super's.
    private func moveRoute(to target: WatchPhoneTarget) -> Bool {
        let route = PlaybackRoute.shared
        switch target {
        case .route:
            return true
        case .iPhone:
            if route.chosen != .device {
                route.switchTo(.device, carrying: false)
            }
            return true
        case let .group(id):
            guard Self.canPlay(onGroup: id) else {
                logger.notice("The watch asked for a speaker that's gone or needs Super")
                return false
            }
            if route.destination != .group(id) {
                route.switchTo(.group(id), carrying: false)
            }
            return true
        }
    }

    /// A Sonos group in reach that this iPhone may play to (without Super,
    /// the free one).
    private static func canPlay(onGroup id: String) -> Bool {
        let sonos = SonosService.shared
        return sonos.isAvailable && sonos.groups.contains { $0.coordinatorID == id } && FeatureGate.shared.isGroupUnlocked(id)
    }

    /// The watch's Play On moving what plays here to another route, carried
    /// across as the player's own Play On carries it.
    private func switchRoute(to id: String) {
        let route = PlaybackRoute.shared
        if id == WatchPhoneRoutes.iPhoneID {
            route.switchTo(.device)
        } else if Self.canPlay(onGroup: id) {
            route.switchTo(.group(id))
        }
    }

    /// Where this iPhone can play, for the watch's Play On: itself, then each
    /// group it may play to, by name, with the one its player is on.
    fileprivate func routesForWatch() -> [String: Any] {
        var routes = [WatchPhoneRoutes.Route(id: WatchPhoneRoutes.iPhoneID, name: "iPhone")]
        let sonos = SonosService.shared
        if sonos.isAvailable {
            routes += sonos.groups
                .filter { FeatureGate.shared.isGroupUnlocked($0.coordinatorID) }
                .map { WatchPhoneRoutes.Route(id: $0.coordinatorID, name: $0.nameWithCount) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        let current = PlaybackRoute.shared.presented.group?.coordinatorID ?? WatchPhoneRoutes.iPhoneID
        return (try? WatchSyncMessage.routesMessage(WatchPhoneRoutes(routes: routes, current: current))) ?? [:]
    }

    /// The songs of a watch pick, as this iPhone plays them: read from the
    /// server by the ids the watch has, as the watch reads them. An artist
    /// is its albums' songs, bounded as on the watch (30 albums, 200 songs).
    /// Nil when the server couldn't be asked.
    private static func songs(for pick: WatchPick) async -> [PlayableContent]? {
        let plex = PlexAPI.shared
        let subsonic = SubsonicAPI.shared
        let ratingKey = ConvertedStream.plexRatingKey(contentID: pick.id) ?? pick.id
        // `toPlayable` needs the Sonos-style id a Plex row plays by.
        func playable(_ metadata: [PlexMetadata]) -> [PlayableContent] {
            metadata.filter { $0.sonosID != nil }.map(\.toPlayable)
        }
        switch (pick.source, pick.kind) {
        case (.plex, .song):
            return await plex.lookupPlexSong(key: ratingKey)?.metadata.map(playable)
        case (.plex, .album):
            return await plex.lookupAlbumTracks(key: ratingKey)?.metadata.map(playable)
        case (.plex, .playlist):
            // Paged: Plex caps each response at 200.
            var fetched: [PlexMetadata] = []
            for _ in 0 ..< 50 {
                guard let page = await plex.lookupPlaylist(key: ratingKey, type: .song, ascending: true, offset: fetched.count) else {
                    return fetched.isEmpty ? nil : playable(fetched)
                }
                fetched += page.metadata
                if page.metadata.count < 200 || fetched.count >= (page.totalSize ?? .max) { break }
            }
            return playable(fetched)
        case (.plex, .artist):
            guard let albums = await plex.lookupArtistAlbums(key: ratingKey)?.metadata else { return nil }
            let keys = albums.prefix(30).map(\.ratingKey)
            let byAlbum = await withTaskGroup(of: (Int, [PlexMetadata]).self) { group in
                for (index, key) in keys.enumerated() {
                    group.addTask { (index, await plex.lookupAlbumTracks(key: key)?.metadata ?? []) }
                }
                var results = [[PlexMetadata]](repeating: [], count: keys.count)
                for await (index, tracks) in group {
                    results[index] = tracks
                }
                return results
            }
            return Array(playable(byAlbum.flatMap { $0 }).prefix(200))
        case (.subsonic, .song):
            return await subsonic.song(for: pick.id).map { [$0.toPlayable] }
        case (.subsonic, .album):
            return await subsonic.album(for: pick.id).map { ($0.song ?? []).map(\.toPlayable) }
        case (.subsonic, .playlist):
            return await subsonic.playlist(for: pick.id).map { ($0.entry ?? []).map(\.toPlayable) }
        case (.subsonic, .artist):
            guard let artist = await subsonic.artist(for: pick.id) else { return nil }
            let ids = (artist.album ?? []).prefix(30).map(\.id)
            let byAlbum = await withTaskGroup(of: (Int, [SubsonicSong]).self) { group in
                for (index, id) in ids.enumerated() {
                    group.addTask { (index, await subsonic.album(for: id)?.song ?? []) }
                }
                var results = [[SubsonicSong]](repeating: [], count: ids.count)
                for await (index, songs) in group {
                    results[index] = songs
                }
                return results
            }
            return Array(byAlbum.flatMap { $0 }.map(\.toPlayable).prefix(200))
        default:
            return nil
        }
    }

    /// The chapters of the book playing here, for the watch's player of it;
    /// none for anything else.
    fileprivate func chaptersForWatch() -> [String: Any] {
        let books = AudiobookPlayer.shared
        var chapters = WatchPhoneChapters(bookKey: nil, chapters: [])
        if let book = books.current, books.isPlayingBook(on: PlaybackRoute.shared.presented) {
            chapters.bookKey = Self.pick(for: book.book)?.key
            chapters.chapters = book.chapters.map {
                WatchPhoneChapters.Chapter(id: $0.id, title: $0.title, start: $0.start, end: $0.end)
            }
        }
        return (try? WatchSyncMessage.chaptersMessage(chapters)) ?? [:]
    }

    /// The queue the player plays from, for the watch's Up Next: from the
    /// song playing on, or the one the queue waits on behind a station, as
    /// many as `WatchPhoneQueue.limit`. A speaker's is read from it, that
    /// stretch only; on radio or TV, from its top.
    fileprivate func queueForWatch() async -> [String: Any] {
        let route = PlaybackRoute.shared
        let limit = WatchPhoneQueue.limit
        let queue: WatchPhoneQueue
        if let group = route.presentedGroup {
            let sonos = SonosService.shared
            // Read afresh, as the player's Up Next does: the cached one lags
            // a source changed from another controller.
            let service = await sonos.playbackService(ip: group.ip) ?? group.playbackService
            let current = service == .queue ? group.coordinatorRoom.track.position : 0
            let items = await sonos.getQueue(ip: group.ip, with: max(0, current - 1), total: limit)
            let songs = items.compactMap { item -> WatchPhoneQueue.Song? in
                guard let position = item.metadata?.position else { return nil }
                return WatchPhoneQueue.Song(position: position, title: item.title, artist: Self.artist(of: item))
            }
            queue = WatchPhoneQueue(
                songs: songs,
                current: current > 0 ? current : nil,
                count: max(group.coordinatorRoom.queueTotal, songs.last?.position ?? 0)
            )
        } else {
            let playback = LocalPlaybackService.shared
            let items = playback.queue
            let start = items.indices.contains(playback.currentIndex) ? playback.currentIndex : 0
            let songs = items.dropFirst(start).prefix(limit).enumerated().map { offset, item in
                WatchPhoneQueue.Song(position: start + offset + 1, title: item.title, artist: Self.artist(of: item))
            }
            queue = WatchPhoneQueue(
                songs: songs,
                current: items.isEmpty || playback.isPlayingStation ? nil : start + 1,
                count: items.count
            )
        }
        return (try? WatchSyncMessage.queueMessage(queue)) ?? [:]
    }

    /// The artist line of a queue row, as the player's: none when empty.
    private static func artist(of item: PlayableContent) -> String? {
        let artist = item.metadata?.artist ?? item.subtitle
        return artist.isEmpty ? nil : artist
    }

    private func nowPlayingMessage(_ now: NowPlaying?) async -> [String: Any] {
        var nowPlaying: WatchPhoneNowPlaying?
        if let now {
            nowPlaying = watchNowPlaying(now, artwork: await Self.watchArtwork(for: now.item, url: now.state.artworkURL))
        }
        return (try? WatchSyncMessage.nowPlayingMessage(nowPlaying)) ?? [:]
    }

    /// What plays, as the watch reads it, with the clock read now.
    private func watchNowPlaying(_ now: NowPlaying, artwork: Data?) -> WatchPhoneNowPlaying {
        WatchPhoneNowPlaying(
            title: now.state.title,
            artist: now.state.artist,
            destination: now.state.destination,
            isOnSpeaker: now.state.isOnSpeaker,
            isPlaying: now.state.isPlaying,
            isBook: now.state.isBook,
            canGoBack: now.state.canGoBack,
            hasNext: now.state.hasNext,
            queuePosition: now.state.queuePosition,
            queueCount: now.state.queueCount,
            artwork: artwork,
            // Read as it goes, after the cover: the clock has run on.
            elapsed: now.clock.elapsed(at: .now),
            duration: now.state.duration,
            clockAt: .now,
            rate: now.clock.rate,
            chapter: now.state.chapter,
            chapterID: now.state.chapterID,
            chapterStart: now.state.chapterStart,
            bookKey: now.state.bookKey,
            sleepsAt: now.state.sleepsAt,
            sleepsAtEnd: now.state.sleepsAtEnd
        )
    }

    /// The cover, 160 px square as a JPEG of a few KB: from the player's
    /// own copy, which is in memory while it's on screen.
    private static func watchArtwork(for item: PlayableContent, url: URL?) async -> Data? {
        guard let url else { return nil }
        // A book's file sends its Audible edition's cover, as the player
        // shows it.
        let cover = await MainActor.run { ContentArtworkView.drawnContent(for: item) }
        let coverURL = cover.id == item.id ? url : cover.artwork ?? cover.thumbnail ?? url
        let request = ContentArtworkView.artworkRequest(for: cover, url: coverURL, preferredSize: ContentArtworkView.playerPreferredSize)
        guard let image = try? await ImagePipeline.shared.image(for: request), image.size.width > 0, image.size.height > 0 else { return nil }
        let side: CGFloat = 160
        let scale = max(side / image.size.width, side / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2, width: drawn.width, height: drawn.height))
        }
        return small.jpegData(compressionQuality: 0.7)
    }
    #endif

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
/// What the watch asks of the playback here, each answered with what
/// plays then. Read off WatchConnectivity's queue, as its messages
/// aren't `Sendable`.
private enum WatchAsk: Sendable {
    case nowPlaying
    case command(WatchPhoneCommand)
    case playQueue(Int)
    case playChapter(Int)
    case sleepTimer(WatchPhoneSleep)
    case speed(Double)
    case playBook(WatchPick, place: WatchBookPlace?, time: TimeInterval?, target: WatchPhoneTarget)
    case playItem(WatchPick, songID: String?, shuffled: Bool, target: WatchPhoneTarget)
    case switchRoute(String)

    init?(_ message: [String: Any]) {
        if let command = WatchSyncMessage.command(in: message) {
            self = .command(command)
        } else if let position = WatchSyncMessage.queuePositionToPlay(in: message) {
            self = .playQueue(position)
        } else if let chapter = WatchSyncMessage.chapterToPlay(in: message) {
            self = .playChapter(chapter)
        } else if let sleep = WatchSyncMessage.sleepTimer(in: message) {
            self = .sleepTimer(sleep)
        } else if let rate = WatchSyncMessage.speed(in: message) {
            self = .speed(rate)
        } else if let book = WatchSyncMessage.bookToPlay(in: message) {
            self = .playBook(book.pick, place: book.place, time: book.time, target: book.target)
        } else if let item = WatchSyncMessage.itemToPlay(in: message) {
            self = .playItem(item.pick, songID: item.songID, shuffled: item.shuffled, target: item.target)
        } else if let route = WatchSyncMessage.routeToSwitch(in: message) {
            self = .switchRoute(route)
        } else if WatchSyncMessage.isNowPlayingRequest(message) {
            self = .nowPlaying
        } else {
            return nil
        }
    }
}

/// The session's delegate, off the main actor because WatchConnectivity
/// calls it on its own queue; everything it hears goes to the service.
private final class WatchSessionRelay: NSObject, WCSessionDelegate, @unchecked Sendable {
    weak var service: WatchSyncService?

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        let picks = WatchSyncMessage.picks(in: session.receivedApplicationContext)
        let places = WatchSyncMessage.places(in: session.receivedApplicationContext)
        let held = WatchSyncMessage.held(in: session.receivedApplicationContext)
        Task { @MainActor in
            if picks != nil || places != nil || held != nil {
                self.service?.didReceive(picks: picks, places: places, held: held)
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

    /// The watch app opened or closed (or went out of reach).
    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.service?.reachabilityDidChange(reachable)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let picks = WatchSyncMessage.picks(in: applicationContext)
        let places = WatchSyncMessage.places(in: applicationContext)
        let held = WatchSyncMessage.held(in: applicationContext)
        guard picks != nil || places != nil || held != nil else { return }
        Task { @MainActor in
            self.service?.didReceive(picks: picks, places: places, held: held)
        }
    }

    /// The watch asking for the sign-ins afresh (its Audiobookshelf token is
    /// about to run out), what plays here, or to play, pause or skip it; for
    /// the queue, or to play a song in it; for a book's chapters, to play
    /// one, for a sleep timer or a speed, or to play one of its books here.
    /// The system wakes Cue to answer.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let reply = UncheckedReply(send: replyHandler)
        if let ask = WatchAsk(message) {
            Task { @MainActor in
                guard let service = self.service else {
                    reply.send([:])
                    return
                }
                reply.send(await service.answer(ask))
            }
            return
        }
        if WatchSyncMessage.isChaptersRequest(message) {
            Task { @MainActor in
                reply.send(self.service?.chaptersForWatch() ?? [:])
            }
            return
        }
        if WatchSyncMessage.isRoutesRequest(message) {
            Task { @MainActor in
                reply.send(self.service?.routesForWatch() ?? [:])
            }
            return
        }
        if WatchSyncMessage.isQueueRequest(message) {
            Task { @MainActor in
                guard let service = self.service else {
                    reply.send([:])
                    return
                }
                reply.send(await service.queueForWatch())
            }
            return
        }
        guard WatchSyncMessage.isCredentialsRequest(message) else {
            replyHandler([:])
            return
        }
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
