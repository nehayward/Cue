import SwiftUI
import WatchSync

/// Now Playing for what the iPhone plays (`PhoneNowPlaying`), opened from
/// the home screen's card while it shows the iPhone's, or by watchOS
/// bringing Cue up as the iPhone starts playing: the cover, the song
/// and its artist (a book and its author), and Previous, Play and Next,
/// each press carried out by the iPhone's own player, here or on its Sonos
/// group — a book's skip back 15 s and ahead 30 s, as there. Over the
/// cover's gradient, titled with where it plays. Music from a queue has
/// Up Next top right (`PhoneQueueScreen`).
///
/// Not the system's `NowPlayingView`, which picks its source itself: with
/// a book loaded on the watch it showed the watch's book, whatever the card
/// said.
struct PhoneNowPlayingScreen: View {
    @Environment(PhoneNowPlaying.self) private var phone
    @Environment(\.zoomNamespace) private var zoom

    var body: some View {
        Group {
            if let playing = phone.current {
                player(playing)
            } else if phone.isAwaitingAnswer {
                // Opened as the iPhone started playing: its song is on the way.
                ProgressView()
            } else {
                notPlaying
            }
        }
        .containerBackground(for: .navigation) {
            ImageMeshFill(image: phone.artwork)
        }
        .toolbar {
            // A book's files aren't songs to pick from.
            if let playing = phone.current, !playing.isBook, playing.queueCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: HomeRoute.phoneQueue) {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("Up Next")
                    .zoomSource(HomeRoute.phoneQueue, in: zoom)
                }
            }
        }
    }

    private func player(_ playing: WatchPhoneNowPlaying) -> some View {
        VStack(spacing: 6) {
            PhoneArtwork(image: phone.artwork, symbol: playing.isBook ? "book.closed" : "music.note")
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 0) {
                Text(playing.title)
                    .font(.headline)
                    .lineLimit(1)
                if let artist = playing.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            transport(playing)
        }
        .navigationTitle(playing.destination)
    }

    /// Previous, play or pause, Next; a book's back 15 s and ahead 30 s.
    /// Play is the screen's primary action, so double tap presses it.
    private func transport(_ playing: WatchPhoneNowPlaying) -> some View {
        HStack {
            Button {
                phone.perform(.previous)
            } label: {
                TransportIcon(symbol: playing.isBook ? "gobackward.15" : "backward.fill", font: .title3)
            }
            .accessibilityLabel(playing.isBook ? "Back 15 Seconds" : "Previous")
            .disabled(!playing.canGoBack)
            Button {
                phone.togglePlayPause()
            } label: {
                TransportIcon(symbol: playing.isPlaying ? "pause.fill" : "play.fill", font: .title)
            }
            .accessibilityLabel(playing.isPlaying ? "Pause" : "Play")
            .primaryHandGesture()
            Button {
                phone.perform(.next)
            } label: {
                TransportIcon(symbol: playing.isBook ? "goforward.30" : "forward.fill", font: .title3)
            }
            .accessibilityLabel(playing.isBook ? "Ahead 30 Seconds" : "Next")
            .disabled(!playing.hasNext)
        }
        .buttonStyle(.plain)
    }

    /// Stopped on the iPhone, or the iPhone went out of reach, while open.
    private var notPlaying: some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(phone.isPhoneInReach ? "Nothing playing on iPhone" : "iPhone out of reach")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// A transport button's glyph, the whole third of the row taking the tap.
private struct TransportIcon: View {
    let symbol: String
    let font: Font

    var body: some View {
        Image(systemName: symbol)
            .font(font)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }
}
