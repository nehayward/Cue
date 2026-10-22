import SwiftUI
import WatchSync

/// What's playing, at the top of the home screen whichever library is on
/// show: the watch's own (`WatchPlayer`), or the iPhone's (`PhoneNowPlaying`,
/// with where it plays under it) while the watch has nothing playing. The
/// cover, the song and its artist (a book and its author), and a waveform
/// that moves while it plays, on the cover's own gradient
/// (`WatchArtworkMesh`), as behind the iPhone's player. The home screen
/// opens the player of the one it shows from it (`NowPlayingScreen` for
/// the watch's, `PhoneNowPlayingScreen` for the iPhone's); play and pause
/// stay on the bottom bar's right edge.
struct NowPlayingCard: View {
    @Environment(WatchPlayer.self) private var player
    @Environment(PhoneNowPlaying.self) private var phone
    /// The iPhone's playback rather than the watch's.
    let showsPhone: Bool

    var body: some View {
        if showsPhone, let playing = phone.current {
            CardLayout(title: playing.title, subtitle: playing.artist ?? "", isPlaying: playing.isPlaying) {
                PhoneArtwork(image: phone.artwork, symbol: playing.isBook ? "book.closed" : "music.note")
            } place: {
                Label(playing.destination, systemImage: playing.isOnSpeaker ? "hifispeaker.fill" : "iphone")
            } fill: {
                ImageMeshFill(image: phone.artwork)
            }
        } else {
            let artwork = player.book?.artworkURL ?? player.current?.artworkURL
            CardLayout(title: player.nowPlayingTitle ?? "", subtitle: player.nowPlayingArtist ?? "", isPlaying: player.isPlaying) {
                ArtworkView(url: artwork, symbol: player.book == nil ? "music.note" : "book.closed")
            } place: {
                EmptyView()
            } fill: {
                CoverMeshFill(url: artwork)
            }
        }
    }
}

/// The card itself: the cover, two lines and a waveform, on a fill.
private struct CardLayout<Cover: View, Place: View, Fill: View>: View {
    let title: String
    let subtitle: String
    let isPlaying: Bool
    @ViewBuilder let cover: Cover
    /// Where it plays, when that's somewhere else.
    @ViewBuilder let place: Place
    @ViewBuilder let fill: Fill

    var body: some View {
        HStack(spacing: 8) {
            cover
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                place
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "waveform")
                .font(.footnote)
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                .foregroundStyle(.white.opacity(isPlaying ? 0.9 : 0.5))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            fill
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now Playing, \(title)")
    }
}

/// A card pressed in a little while held, as a list row is.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The cover the iPhone sent, as `ArtworkView` draws one.
struct PhoneArtwork: View {
    let image: UIImage?
    let symbol: String

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// A cover's gradient filling a card, a little darker for the white text:
/// a plain grey until it's made, then crossfading in, and from one cover's
/// to the next.
private struct MeshFill: View {
    let gradient: UIImage?

    var body: some View {
        ZStack {
            Color.gray.opacity(0.3)
            if let gradient {
                Image(uiImage: gradient)
                    .resizable()
                    .interpolation(.high)
                    .id(gradient)
                    .transition(.opacity)
            }
            Color.black.opacity(0.2)
        }
        .animation(.smooth(duration: 0.8), value: gradient)
    }
}

/// The gradient of a cover on the watch, from `ArtworkStore`'s copy.
struct CoverMeshFill: View {
    let url: URL?

    @State private var gradient: UIImage?

    init(url: URL?) {
        self.url = url
        // One already made is there in the first frame, rather than fading
        // in over grey each time the home screen comes back.
        _gradient = State(initialValue: WatchArtworkMesh.made(for: url))
    }

    var body: some View {
        MeshFill(gradient: gradient)
            .task(id: url) {
                guard let url else {
                    gradient = nil
                    return
                }
                guard let made = await WatchArtworkMesh.gradient(for: url), !Task.isCancelled else { return }
                gradient = made
            }
    }
}

/// The gradient of the cover the iPhone sent, made off the main thread.
struct ImageMeshFill: View {
    let image: UIImage?

    @State private var gradient: UIImage?

    var body: some View {
        MeshFill(gradient: gradient)
            .task(id: image) {
                guard let image else {
                    gradient = nil
                    return
                }
                let made = await Task.detached(priority: .utility) {
                    WatchArtworkMesh.gradient(for: image)
                }.value
                guard !Task.isCancelled else { return }
                gradient = made
            }
    }
}
