import SwiftUI
import WatchKit
import WatchSync

/// Where a play goes: this watch, or Cue on the iPhone — asked each time
/// while the iPhone's in reach (`PhoneConnection.canReachPhone`), straight
/// to the watch otherwise. Then the player of where it went opens on the
/// home screen's stack: the watch's Now Playing, or the iPhone's
/// (`PhoneNowPlayingScreen`, which the iPhone's answer has filled in). Each
/// screen that plays keeps one and shows its sheet (`playOnSheet(_:)`).
@MainActor
@Observable
final class PlayOn {
    struct Request {
        let songs: [WatchSong]
        let startKey: String?
        let shuffled: Bool
    }

    enum Stage {
        case choosing(Request)
        case sending
        case failed(String, Request)
    }

    /// What the sheet shows; nil while it's down.
    var stage: Stage?
    /// The player to open once the sheet is down.
    var playerAfterSheet: HomeRoute?
    /// The player to open now: played with no sheet up.
    var playerNow: HomeRoute?
    /// The latest play handed to the iPhone, so an answer that comes after
    /// a newer play changes nothing.
    @ObservationIgnored private var sending: UUID?

    /// Plays `songs` from the one with `key`, or shuffled with that one
    /// first — asking where, while the iPhone's in reach.
    func play(_ songs: [WatchSong], startingAt key: String? = nil, shuffled: Bool = false) {
        guard !songs.isEmpty else { return }
        let request = Request(songs: songs, startKey: key, shuffled: shuffled)
        if PhoneConnection.shared.canReachPhone {
            stage = .choosing(request)
        } else {
            playOnWatch(request)
        }
    }

    /// Downloaded songs from their files, the rest streamed.
    func playOnWatch(_ request: Request) {
        sending = nil
        guard WatchPlayer.shared.play(request.songs, startingAt: request.startKey, shuffled: request.shuffled) else {
            stage = nil
            return
        }
        open(.nowPlaying)
    }

    /// Cue on the iPhone plays them, on the phone or its speakers. The
    /// watch stops its own, so there's one player at a time.
    func playOnPhone(_ request: Request) {
        let id = UUID()
        sending = id
        stage = .sending
        WKInterfaceDevice.current().play(.click)
        let (songs, start) = WatchPlayer.order(request.songs, startingAt: request.startKey, shuffled: request.shuffled)
        let message = WatchPlayRequest(songs: songs.map(\.playRequestSong), startIndex: start)
        Task {
            let failure = await PhoneConnection.shared.play(message)
            guard sending == id else { return }
            sending = nil
            // One player at a time, even when the sheet was closed meanwhile.
            if failure == nil, WatchPlayer.shared.current != nil {
                WatchPlayer.shared.stop()
            }
            // Closed while it was on its way.
            guard case .sending? = stage else { return }
            if let failure {
                WKInterfaceDevice.current().play(.failure)
                stage = .failed(failure, request)
            } else {
                WKInterfaceDevice.current().play(.success)
                open(.phoneNowPlaying)
            }
        }
    }

    /// Once the sheet is down, when it's up: one presentation at a time.
    private func open(_ player: HomeRoute) {
        if stage == nil {
            playerNow = player
        } else {
            playerAfterSheet = player
            stage = nil
        }
    }
}

extension View {
    /// The Play On choice for `playOn`'s plays, and the player after it.
    func playOnSheet(_ playOn: PlayOn) -> some View {
        modifier(PlayOnPresenter(playOn: playOn))
    }
}

private struct PlayOnPresenter: ViewModifier {
    let playOn: PlayOn
    @Environment(\.openPlayer) private var openPlayer

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: isPresented, onDismiss: {
                if let player = playOn.playerAfterSheet {
                    playOn.playerAfterSheet = nil
                    openPlayer(player)
                }
            }) {
                PlayOnSheet(playOn: playOn)
            }
            .onChange(of: playOn.playerNow) { _, player in
                guard let player else { return }
                playOn.playerNow = nil
                openPlayer(player)
            }
    }

    private var isPresented: Binding<Bool> {
        Binding {
            playOn.stage != nil
        } set: { isPresented in
            if !isPresented {
                playOn.stage = nil
            }
        }
    }
}

private struct PlayOnSheet: View {
    let playOn: PlayOn

    var body: some View {
        switch playOn.stage {
        case let .choosing(request)?:
            List {
                Section {
                    Button {
                        playOn.playOnWatch(request)
                    } label: {
                        Label("This Watch", systemImage: "applewatch")
                    }
                    Button {
                        playOn.playOnPhone(request)
                    } label: {
                        Label("iPhone", systemImage: "iphone")
                    }
                } header: {
                    Text("Play On")
                } footer: {
                    Text("On iPhone, Cue plays them on the phone or the speakers it's set to.")
                }
            }
        case .sending?:
            ProgressView("Starting on iPhone…")
        case let .failed(message, request)?:
            ScrollView {
                VStack(spacing: 10) {
                    Text(message)
                        .multilineTextAlignment(.center)
                    Button {
                        playOn.playOnWatch(request)
                    } label: {
                        Label("Play on This Watch", systemImage: "applewatch")
                    }
                }
            }
        case nil:
            EmptyView()
        }
    }
}

/// Opens a player on the home screen's stack, from any screen in it: the
/// watch's Now Playing or the iPhone's.
struct OpenPlayerKey: EnvironmentKey {
    static let defaultValue: @MainActor (HomeRoute) -> Void = { _ in }
}

extension EnvironmentValues {
    var openPlayer: @MainActor (HomeRoute) -> Void {
        get { self[OpenPlayerKey.self] }
        set { self[OpenPlayerKey.self] = newValue }
    }
}
