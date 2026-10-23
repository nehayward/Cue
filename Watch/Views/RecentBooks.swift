import MusicSearchKit
import SwiftUI
import WatchSync

/// The book on the watch last listened to, at the top of the Audiobooks
/// library on its cover's gradient: what's left of it and how far it's got,
/// and a tap plays it from where it was left (pauses it while it plays).
struct BookBanner: View {
    @Environment(WatchPlayer.self) private var player
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchBookStore.self) private var books
    let pick: WatchPick

    var body: some View {
        let isPlaying = player.book?.key == pick.key && player.isPlaying
        let progress = books.progress(for: pick.key)
        let duration = store.songsByPick[pick.key]?.reduce(0.0) { $0 + ($1.duration ?? 0) } ?? 0
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                ArtworkView(url: pick.artworkURL, symbol: "book.closed")
                    .frame(width: 56, height: 56)
                Spacer(minLength: 0)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.2), in: Circle())
            }
            Text(pick.title)
                .font(.headline)
                .lineLimit(2)
            Text(WatchBookFormat.status(progress, duration: duration))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
                .monospacedDigit()
            ProgressView(value: fraction(progress, duration: duration))
                .tint(.white)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            CoverMeshFill(url: pick.artworkURL)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isPlaying ? "Pause" : "Play") \(pick.title)")
    }
}

/// One of the two books listened to before the banner's, beside the other:
/// its cover with how far it's got along the foot, and its title.
struct BookTile: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchBookStore.self) private var books
    let pick: WatchPick

    var body: some View {
        let duration = store.songsByPick[pick.key]?.reduce(0.0) { $0 + ($1.duration ?? 0) } ?? 0
        VStack(alignment: .leading, spacing: 4) {
            ArtworkView(url: pick.artworkURL, symbol: "book.closed")
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    ProgressView(value: fraction(books.progress(for: pick.key), duration: duration))
                        .tint(.white)
                        .padding(6)
                }
            Text(pick.title)
                .font(.footnote)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// How far into a book its place is, 0 to 1.
private func fraction(_ progress: AudiobookProgress?, duration: TimeInterval) -> Double {
    guard let progress else { return 0 }
    let total = progress.duration > 0 ? progress.duration : duration
    guard total > 0 else { return 0 }
    return min(max(progress.position / total, 0), 1)
}
