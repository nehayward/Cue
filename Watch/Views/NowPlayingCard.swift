import SwiftUI

/// What's playing, at the top of the home screen whichever library is on
/// show: the cover, the song and its artist (a book and its author), and a
/// waveform that moves while it plays, on the cover's own gradient
/// (`WatchArtworkMesh`), as behind the iPhone's player. The home screen
/// opens Now Playing from it; play and pause stay on the bottom bar's
/// right edge.
struct NowPlayingCard: View {
    @Environment(WatchPlayer.self) private var player

    var body: some View {
        let artwork = player.book?.artworkURL ?? player.current?.artworkURL
        HStack(spacing: 8) {
            ArtworkView(url: artwork, symbol: player.book == nil ? "music.note" : "book.closed")
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text(player.nowPlayingTitle ?? "")
                    .font(.headline)
                    .lineLimit(1)
                Text(player.nowPlayingArtist ?? "")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "waveform")
                .font(.footnote)
                .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                .foregroundStyle(.white.opacity(player.isPlaying ? 0.9 : 0.5))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            CoverMeshFill(url: artwork)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now Playing, \(player.nowPlayingTitle ?? "")")
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

/// A cover's gradient filling a card, a little darker for the white text:
/// a plain grey until it's made, then crossfading in, and from one cover's
/// to the next.
private struct CoverMeshFill: View {
    let url: URL?

    @State private var gradient: UIImage?

    init(url: URL?) {
        self.url = url
        // One already made is there in the first frame, rather than fading
        // in over grey each time the home screen comes back.
        _gradient = State(initialValue: WatchArtworkMesh.made(for: url))
    }

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
