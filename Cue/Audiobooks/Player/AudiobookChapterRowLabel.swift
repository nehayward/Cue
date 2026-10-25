import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// A chapter's row: a bookmark, its title, where it starts and how long it
/// runs. `isHere` marks the listener's chapter, in the accent; `isDone` one
/// before their place, its bookmark filled and its title dimmed, so the
/// list reads as how far the book has got. The book's page and the
/// chapters sheet both list them so. With `book`, the listener's chapter is
/// filled behind as far as it's been heard (`AudiobookChapterProgressFill`).
struct AudiobookChapterRowLabel: View {
    let chapter: AudiobookChapter
    let isHere: Bool
    var isDone = false
    /// The book the chapter is in, for the fill on the listener's chapter.
    var book: PlayableContent?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isHere || isDone ? "bookmark.fill" : "bookmark")
                .foregroundStyle(.primary.opacity(isHere ? 1 : isDone ? 0.6 : 0.35))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .foregroundStyle(.primary.opacity(isDone ? 0.6 : 1))
                    .fontWeight(isHere ? .semibold : .regular)
                Text(AudiobookFormat.clock(chapter.start))
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.6))
                    .monospacedDigit()
            }
            Spacer()
            // Dimmed with a chapter that's done, never brighter than its
            // title.
            Text(AudiobookFormat.duration(chapter.duration))
                .font(.caption)
                .foregroundStyle(.primary.opacity(isDone ? 0.6 : 0.8))
        }
        // The listener's chapter is the accent throughout: its primary is
        // the accent. Levels are opacities of primary, never `.secondary`
        // or `.tertiary`, which flicker as the glass sheet changes.
        .foregroundStyle(isHere ? AnyShapeStyle(.tint) : AnyShapeStyle(.foreground))
        .padding(.vertical, 10)
        .background {
            if isHere, let book {
                AudiobookChapterProgressFill(chapter: chapter, book: book)
                    // A little past the row's content, so the fill reads
                    // as the row rather than a box round the words.
                    .padding(.horizontal, -10)
                    .padding(.vertical, 2)
            }
        }
        .contentShape(.rect)
    }
}

/// The listener's chapter, filled behind its row as far as it's been heard:
/// the row's width is the chapter. A view of its own because it reads the
/// place, which moves every couple of seconds while the book plays, so only
/// the fill redraws, not the list; it eases between readings rather than
/// stepping. The player's place while it has the book, else the place kept
/// for it.
struct AudiobookChapterProgressFill: View {
    let chapter: AudiobookChapter
    let book: PlayableContent

    @State private var player = AudiobookPlayer.shared
    @State private var store = AudiobookProgressStore.shared

    private var fraction: Double {
        let position = player.isLoaded(book) ? player.position : store.progress(for: book)?.position
        guard let position, chapter.duration > 0 else { return 0 }
        return min(max((position - chapter.start) / chapter.duration, 0), 1)
    }

    var body: some View {
        let fraction = fraction
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        GeometryReader { geo in
            Rectangle()
                .fill(Color.accent.opacity(0.18))
                .frame(width: geo.size.width * fraction)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.accent.opacity(0.06))
        .clipShape(shape)
        .animation(.linear(duration: 2), value: fraction)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
