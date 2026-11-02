import SwiftUI
import WatchConnectivity
import WatchKit
import WatchSync

/// Something to play, waiting on where: here (when the watch has it), or
/// on one of the iPhone's routes.
struct PlayRequest: Identifiable {
    let id = UUID()
    let title: String
    /// Plays it here; nil when the watch hasn't got it to play.
    let playHere: (@MainActor () -> Void)?
    let playOnPhone: @MainActor (WatchPhoneTarget) -> Void
}

/// Plays here or on the iPhone. With the iPhone in reach Play asks which
/// (`askingWhereToPlay`); out of reach it plays here.
@MainActor
enum PlayChoice {
    /// The iPhone's there to ask: in reach, and heard from (or the session
    /// up), so a choice of it goes somewhere.
    static var canAskPhone: Bool {
        let phone = PhoneNowPlaying.shared
        return phone.isPhoneInReach && (WCSession.default.isReachable || phone.current != nil)
    }

    /// Asks where, with the iPhone there; else plays here (a failure tap
    /// when the watch hasn't got it).
    static func ask(_ title: String, playHere: (@MainActor () -> Void)?, playOnPhone: @escaping @MainActor (WatchPhoneTarget) -> Void) -> PlayRequest? {
        if canAskPhone {
            PhoneNowPlaying.shared.refreshRoutes()
            return PlayRequest(title: title, playHere: playHere, playOnPhone: playOnPhone)
        }
        if let playHere {
            playHere()
        } else {
            WKInterfaceDevice.current().play(.failure)
        }
        return nil
    }

    /// An album, playlist, artist or song from the watch's library: here,
    /// with `playHere` while the watch has it, or on the iPhone, from the
    /// song `songID` in it or shuffled. The watch pauses for the iPhone.
    static func play(_ pick: WatchPick, from songID: String? = nil, shuffled: Bool = false, playHere: (@MainActor () -> Void)?) -> PlayRequest? {
        ask(pick.title, playHere: playHere) { target in
            if WatchPlayer.shared.isPlaying {
                WatchPlayer.shared.pause()
            }
            PhoneNowPlaying.shared.playItem(pick, from: songID, shuffled: shuffled, on: target)
        }
    }
}

/// Plays the watch's books here or on the iPhone: Play asks, unless it's
/// the book the watch is in the middle of while the iPhone plays nothing.
@MainActor
enum BookPlayback {
    /// Plays `pick` from `time` (book time, or its place): here, or nothing
    /// yet and the request to ask about.
    static func play(_ pick: WatchPick, from time: TimeInterval?) -> PlayRequest? {
        let player = WatchPlayer.shared
        let phone = PhoneNowPlaying.shared
        let canPlayHere = player.canPlayBook(pick, from: time)
        // Played here this launch, and the iPhone's quiet: it goes on here.
        let isUnderWayHere = player.book?.key == pick.key && player.lastPlayedAt != nil && phone.current?.isPlaying != true
        if isUnderWayHere, canPlayHere {
            playHere(pick, from: time)
            return nil
        }
        var here: (@MainActor () -> Void)?
        if canPlayHere {
            here = { Self.playHere(pick, from: time) }
        }
        return PlayChoice.ask(pick.title, playHere: here) { target in
            Self.playOnPhone(pick, from: time, on: target)
        }
    }

    /// Plays it on the watch. The iPhone, playing the same book, pauses:
    /// two players would each keep their own place.
    static func playHere(_ pick: WatchPick, from time: TimeInterval?) {
        let phone = PhoneNowPlaying.shared
        if let playing = phone.current, playing.bookKey == pick.key, playing.isPlaying {
            phone.togglePlayPause()
        }
        if !WatchPlayer.shared.playBook(pick, from: time) {
            WKInterfaceDevice.current().play(.failure)
        }
    }

    /// Plays it on the iPhone (`target`), from the watch's place where
    /// that's newer: the watch pauses first, keeping its place to send.
    static func playOnPhone(_ pick: WatchPick, from time: TimeInterval?, on target: WatchPhoneTarget) {
        let player = WatchPlayer.shared
        if player.isPlaying {
            player.pauseKeepingPlace()
        }
        PhoneNowPlaying.shared.playBook(pick, from: time, on: target)
    }
}

/// Opens the player of the iPhone's playback over the screen something was
/// sent there from.
struct OpenPhonePlayerKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

extension EnvironmentValues {
    var openPhonePlayer: (@MainActor () -> Void)? {
        get { self[OpenPhonePlayerKey.self] }
        set { self[OpenPhonePlayerKey.self] = newValue }
    }
}

extension View {
    /// Asks where `request` plays — this watch, the iPhone, or a speaker it
    /// plays to — while it's set.
    func askingWhereToPlay(_ request: Binding<PlayRequest?>) -> some View {
        modifier(AskWhereToPlay(request: request))
    }
}

private struct AskWhereToPlay: ViewModifier {
    @Environment(PhoneNowPlaying.self) private var phone
    @Environment(\.openPhonePlayer) private var openPhonePlayer
    @Binding var request: PlayRequest?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Play On",
                isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }),
                titleVisibility: .visible,
                presenting: request
            ) { request in
                if let playHere = request.playHere {
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        playHere()
                    } label: {
                        Label(PlaybackPlace.watch.name, systemImage: PlaybackPlace.watch.symbol)
                    }
                }
                // The iPhone and each speaker it plays to, once it's said;
                // until then the iPhone, and the speaker it's on.
                if let routes = phone.routes?.routes {
                    ForEach(routes) { route in
                        let place: PlaybackPlace = route.isSpeaker ? .speaker(route.name) : .iPhone
                        Button {
                            play(request, on: WatchPhoneTarget(routeID: route.id))
                        } label: {
                            Label(place.name, systemImage: place.symbol)
                        }
                    }
                } else {
                    Button {
                        play(request, on: .iPhone)
                    } label: {
                        Label(PlaybackPlace.iPhone.name, systemImage: PlaybackPlace.iPhone.symbol)
                    }
                    if let playing = phone.current, playing.isOnSpeaker {
                        Button {
                            play(request, on: .route)
                        } label: {
                            Label(playing.destination, systemImage: PlaybackPlace.speaker(playing.destination).symbol)
                        }
                    }
                }
            } message: { request in
                Text(request.title)
            }
    }

    private func play(_ request: PlayRequest, on target: WatchPhoneTarget) {
        WKInterfaceDevice.current().play(.click)
        request.playOnPhone(target)
        openPhonePlayer?()
    }
}
