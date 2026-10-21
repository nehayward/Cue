import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// The same, as a row under Up Next's header, where the queue it brings
/// back is thought of: the music set aside while a book plays, or the book
/// left while music plays, its cover and a Play.
struct BookMusicSwitchRow: View {
    @State private var player = AudiobookPlayer.shared
    private var playback: LocalPlaybackService { .shared }

    var body: some View {
        let isBook = player.contains(playback.nowPlaying)
        if isBook, let aside = player.musicSetAside {
            row(cover: aside.nowPlaying, title: "Your Music", detail: aside.title) {
                try? await player.returnToMusic()
            }
        } else if !isBook, let book = player.bookToReturnTo {
            row(cover: book, title: book.title, detail: "Back to your book") {
                await player.play(book)
            }
        }
    }

    private func row(cover: PlayableContent?, title: String, detail: String, action: @escaping @MainActor () async -> Void) -> some View {
        Button {
            HapticManager.shared.fireHaptic(.buttonPress)
            Task { await action() }
        } label: {
            HStack(spacing: 12) {
                if let cover {
                    ContentArtworkView(content: cover, showMusicSource: false, preferredSize: 120, cornerRadius: 6)
                        .frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
            .padding(10)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityHint("Plays it from where it was left")
    }
}
