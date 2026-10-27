import Observation
import UIKit
import WatchConnectivity
import WatchSync

/// What Cue on the iPhone is playing, for the home screen's card and the
/// player of it: asked for as the app opens and the iPhone comes in reach,
/// then sent by the iPhone as it changes while the app is open. Play, pause
/// and the skips go back to the iPhone (`PhoneConnection.askPhone`), which
/// carries them out as its player's own buttons do; so do a chapter picked,
/// the sleep timer and a book's speed, and a watch book played there. Up
/// Next asks for the queue it plays from (`queue`), a book's chapters for
/// its chapters (`chapters`).
///
/// The session drops whenever the watch app leaves the screen (a lowered
/// wrist), so a drop counts as the iPhone out of reach only once it has
/// lasted a few seconds with the app on screen: until then what the iPhone
/// last said stands, its clock running on, and it's asked afresh as the
/// app comes back.
@MainActor
@Observable
final class PhoneNowPlaying {
    static let shared = PhoneNowPlaying()

    /// The iPhone is in reach: the home screen shows its playback alongside
    /// the watch's, and Play on a book asks where. Taken as in reach until
    /// the session has been out of reach a while on screen.
    private(set) var isPhoneInReach = true
    private(set) var current: WatchPhoneNowPlaying?
    /// The cover, decoded once a song.
    private(set) var artwork: UIImage?
    /// The queue the iPhone plays from, from the song playing on: nil
    /// until it's been asked for and has come.
    private(set) var queue: WatchPhoneQueue?
    /// The chapters of the book the iPhone plays: nil until asked for.
    private(set) var chapters: WatchPhoneChapters?
    /// Where the iPhone can play — itself and its Sonos groups — for Play
    /// On: nil until asked for.
    private(set) var routes: WatchPhoneRoutes?
    /// When the iPhone last said what it plays: what came before the app
    /// last opened may be stale.
    private(set) var heardAt: Date?

    /// The watch app is on screen: only then is a dropped session news.
    @ObservationIgnored private var isAppActive = true
    @ObservationIgnored private var outOfReachCheck: Task<Void, Never>?
    /// How long the session may be down, on screen, before the iPhone is
    /// out of reach: it comes back a second or two after the wrist does.
    private static let reachGrace: Duration = .seconds(6)

    private init() {
        #if DEBUG
        showPreviewIfAsked()
        #endif
    }

    /// Asks the iPhone what it plays.
    func refresh() {
        PhoneConnection.shared.askPhone(WatchSyncMessage.nowPlayingRequest)
    }

    /// Plays or pauses the iPhone, shown at once; its answer settles it.
    func togglePlayPause() {
        perform(.togglePlayPause)
    }

    /// A press for the iPhone's player: play and pause show at once, the
    /// clock held where it is, a skip once the iPhone answers with where it
    /// went.
    func perform(_ command: WatchPhoneCommand) {
        guard current != nil else { return }
        if command == .togglePlayPause, var playing = current {
            let now = Date.now
            playing.elapsed = playing.elapsed(at: now)
            playing.clockAt = now
            playing.isPlaying.toggle()
            current = playing
        }
        PhoneConnection.shared.askPhone(WatchSyncMessage.commandRequest(command))
    }

    /// Asks the iPhone for the queue it plays from.
    func refreshQueue() {
        PhoneConnection.shared.askPhone(WatchSyncMessage.queueRequest)
    }

    /// Plays the song at `position` in the iPhone's queue, as a tap on its
    /// own Up Next does; its answer says what plays then.
    func playFromQueue(at position: Int) {
        guard current != nil else { return }
        PhoneConnection.shared.askPhone(WatchSyncMessage.playQueueRequest(at: position))
    }

    /// Asks the iPhone for the chapters of the book it plays.
    func refreshChapters() {
        PhoneConnection.shared.askPhone(WatchSyncMessage.chaptersRequest)
    }

    /// Plays the iPhone's book from a chapter's start, marked at once.
    func playChapter(_ chapter: WatchPhoneChapters.Chapter) {
        guard var playing = current else { return }
        playing.chapter = chapter.title
        playing.chapterID = chapter.id
        playing.elapsed = 0
        playing.duration = chapter.duration
        playing.clockAt = .now
        current = playing
        PhoneConnection.shared.askPhone(WatchSyncMessage.playChapterRequest(chapter.id))
    }

    /// Sets the sleep timer of what the iPhone plays, shown at once.
    func setSleepTimer(_ sleep: WatchPhoneSleep) {
        guard var playing = current else { return }
        switch sleep {
        case .off:
            playing.sleepsAt = nil
            playing.sleepsAtEnd = false
        case .end:
            playing.sleepsAt = nil
            playing.sleepsAtEnd = true
        case let .minutes(minutes):
            playing.sleepsAt = .now.addingTimeInterval(TimeInterval(minutes * 60))
            playing.sleepsAtEnd = false
        }
        current = playing
        PhoneConnection.shared.askPhone(WatchSyncMessage.sleepTimerRequest(sleep))
    }

    /// Sets the speed of the book the iPhone plays, shown at once.
    func setSpeed(_ rate: Double) {
        guard var playing = current else { return }
        let now = Date.now
        playing.elapsed = playing.elapsed(at: now)
        playing.clockAt = now
        playing.rate = rate
        current = playing
        PhoneConnection.shared.askPhone(WatchSyncMessage.speedRequest(rate))
    }

    /// Asks the iPhone where it can play.
    func refreshRoutes() {
        PhoneConnection.shared.askPhone(WatchSyncMessage.routesRequest)
    }

    /// Moves what the iPhone plays to another of its routes, as its Play On
    /// does; ticked there at once.
    func switchRoute(to id: String) {
        routes?.current = id
        PhoneConnection.shared.askPhone(WatchSyncMessage.switchRouteRequest(to: id))
    }

    /// Plays an album, playlist, artist or song from the watch's library on
    /// the iPhone (`target`): from the song `songID` in it, or shuffled.
    func playItem(_ pick: WatchPick, from songID: String? = nil, shuffled: Bool = false, on target: WatchPhoneTarget) {
        guard let request = try? WatchSyncMessage.playItemRequest(pick, from: songID, shuffled: shuffled, on: target) else { return }
        PhoneConnection.shared.askPhone(request)
    }

    /// Plays one of the watch's books on the iPhone (`target`), from `time`
    /// or its place here, which the iPhone takes where it's newer.
    func playBook(_ pick: WatchPick, from time: TimeInterval?, on target: WatchPhoneTarget) {
        let place = WatchBookStore.shared.places[pick.key]
        guard let request = try? WatchSyncMessage.playBookRequest(pick, place: place, from: time, on: target) else { return }
        PhoneConnection.shared.askPhone(request)
    }

    func apply(queue: WatchPhoneQueue) {
        self.queue = queue
    }

    func apply(chapters: WatchPhoneChapters) {
        self.chapters = chapters
    }

    func apply(routes: WatchPhoneRoutes) {
        self.routes = routes
    }

    /// What the iPhone left in its context, so the card is there the moment
    /// the app opens, before the iPhone answers: not over anything it has
    /// said since, nor when it's old — a playing card past 2 hours, a paused
    /// one past 10 minutes — as Cue on the iPhone may have quit since without
    /// a word. It comes without its cover (the shown one stays for the same
    /// song), and doesn't count as heard: what opens the player waits for
    /// the iPhone's own answer.
    func apply(contextCard card: WatchPhoneNowPlaying?, sentAt: Date) {
        guard sentAt > (heardAt ?? .distantPast) else { return }
        if let card, Date.now.timeIntervalSince(sentAt) > (card.isPlaying ? 2 * 60 * 60 : 10 * 60) { return }
        var card = card
        if let shown = current, card?.title == shown.title, card?.bookKey == shown.bookKey {
            card?.artwork = shown.artwork
        } else {
            artwork = nil
        }
        if card?.bookKey != chapters?.bookKey || card?.isBook != true {
            chapters = nil
        }
        current = card
    }

    func apply(_ nowPlaying: WatchPhoneNowPlaying?) {
        if nowPlaying?.artwork != current?.artwork {
            artwork = nowPlaying?.artwork.flatMap(UIImage.init(data:))
            #if DEBUG
            artwork = artwork.map(WatchScreenshotArtwork.prepared)
            #endif
        }
        // Another book, or none: its chapters go.
        if nowPlaying?.bookKey != chapters?.bookKey || nowPlaying?.isBook != true {
            chapters = nil
        }
        current = nowPlaying
        heardAt = .now
        isPhoneInReach = true
    }

    // MARK: - Reach

    /// The session came back, so the iPhone is asked what it plays; or
    /// dropped, which counts once it's lasted with the app on screen.
    func reachabilityDidChange(_ isReachable: Bool) {
        if isReachable {
            outOfReachCheck?.cancel()
            outOfReachCheck = nil
            isPhoneInReach = true
            refresh()
        } else {
            checkReachLater()
        }
    }

    /// Back on screen: asked afresh, and checked a while later in case the
    /// iPhone went away meanwhile.
    func appDidBecomeActive() {
        isAppActive = true
        if WCSession.default.activationState == .activated, WCSession.default.isReachable {
            reachabilityDidChange(true)
        } else {
            checkReachLater()
        }
    }

    /// Off screen, the session drops with it: that isn't the iPhone going.
    func appDidResignActive() {
        isAppActive = false
        outOfReachCheck?.cancel()
        outOfReachCheck = nil
    }

    private func checkReachLater() {
        guard isAppActive, outOfReachCheck == nil, !isPreview else { return }
        outOfReachCheck = Task { [weak self] in
            try? await Task.sleep(for: Self.reachGrace)
            guard let self, !Task.isCancelled else { return }
            self.outOfReachCheck = nil
            guard self.isAppActive, !WCSession.default.isReachable else { return }
            self.isPhoneInReach = false
            self.current = nil
            self.artwork = nil
            self.queue = nil
            self.chapters = nil
            self.routes = nil
        }
    }

    // MARK: - Preview

    /// A made-up book playing on the iPhone, for the simulator, which has
    /// no iPhone to hear from: `-dance.cue.phonePreview YES` (Debug), with
    /// `-dance.cue.phonePreviewArtwork <image path>` for its cover.
    private var isPreview = false

    #if DEBUG
    private func showPreviewIfAsked() {
        guard UserDefaults.standard.bool(forKey: "dance.cue.phonePreview") else { return }
        isPreview = true
        current = WatchPhoneNowPlaying(
            title: "The Two Towers",
            artist: "J. R. R. Tolkien",
            destination: "iPhone",
            isPlaying: true,
            isBook: true,
            elapsed: 312,
            duration: 1_847,
            clockAt: .now,
            rate: 1.2,
            chapter: "Chapter 12",
            chapterID: 11,
            bookKey: "audiobook-plex-preview",
            sleepsAt: .now.addingTimeInterval(1_200)
        )
        chapters = WatchPhoneChapters(bookKey: "audiobook-plex-preview", chapters: (0 ..< 30).map {
            .init(id: $0, title: "Chapter \($0 + 1)", start: Double($0) * 1_800, end: Double($0 + 1) * 1_800)
        })
        if let path = UserDefaults.standard.string(forKey: "dance.cue.phonePreviewArtwork"),
           let image = UIImage(contentsOfFile: path) {
            artwork = WatchScreenshotArtwork.prepared(image)
        }
    }
    #endif
}
