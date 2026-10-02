import SwiftUI
import WatchKit
import WatchSync

/// Where a play goes: this watch, or Cue on the iPhone — asked each time
/// while the iPhone's in reach, straight to the watch otherwise. Then Now
/// Playing, in the same sheet: the system's, which shows the watch's
/// playback or, once the watch lets go, the iPhone's. Each screen that
/// plays keeps one and shows its sheet (`playOnSheet(_:)`).
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
        case nowPlaying
    }

    /// What the sheet shows; nil while it's down.
    var stage: Stage?

    /// Plays `songs` from the one with `key`, or shuffled with that one
    /// first — asking where, while the iPhone's in reach.
    func play(_ songs: [WatchSong], startingAt key: String? = nil, shuffled: Bool = false) {
        guard !songs.isEmpty else { return }
        let request = Request(songs: songs, startKey: key, shuffled: shuffled)
        if PhoneConnection.shared.isPhoneReachable {
            stage = .choosing(request)
        } else {
            playOnWatch(request)
        }
    }

    /// Downloaded songs from their files, the rest streamed.
    func playOnWatch(_ request: Request) {
        guard WatchPlayer.shared.play(request.songs, startingAt: request.startKey, shuffled: request.shuffled) else {
            stage = nil
            return
        }
        stage = .nowPlaying
    }

    /// Cue on the iPhone plays them, on the phone or its speakers. The
    /// watch stops its own, so Now Playing turns to the iPhone's.
    func playOnPhone(_ request: Request) {
        stage = .sending
        WKInterfaceDevice.current().play(.click)
        let (songs, start) = WatchPlayer.order(request.songs, startingAt: request.startKey, shuffled: request.shuffled)
        let message = WatchPlayRequest(songs: songs.map(\.playRequestSong), startIndex: start)
        Task {
            let reply = await PhoneConnection.shared.play(message)
            // One player at a time, even when the sheet was closed meanwhile.
            if reply.failure == nil, WatchPlayer.shared.current != nil {
                WatchPlayer.shared.stop()
            }
            // Closed while it was on its way.
            guard case .sending? = stage else { return }
            if let failure = reply.failure {
                WKInterfaceDevice.current().play(.failure)
                stage = .failed(failure, request)
            } else {
                WKInterfaceDevice.current().play(.success)
                stage = .nowPlaying
            }
        }
    }
}

extension View {
    /// The Play On choice and Now Playing after it, for `playOn`'s plays.
    func playOnSheet(_ playOn: PlayOn) -> some View {
        modifier(PlayOnPresenter(playOn: playOn))
    }
}

private struct PlayOnPresenter: ViewModifier {
    let playOn: PlayOn

    func body(content: Content) -> some View {
        content.sheet(isPresented: isPresented) {
            PlayOnSheet(playOn: playOn)
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
        case .nowPlaying?, nil:
            NowPlayingView()
        }
    }
}
