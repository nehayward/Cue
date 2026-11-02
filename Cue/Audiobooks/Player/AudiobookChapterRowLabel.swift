import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI
import VibesDS

/// A chapter's row: a bookmark, its title, where it starts and how long it
/// runs. `isHere` marks the listener's chapter: its bookmark in the accent,
/// its title bold and in the primary colour, readable over its fill; `isDone` one
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
                .foregroundStyle(isHere ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(isDone ? 0.6 : 0.35)))
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
        // Levels are opacities of primary, never `.secondary` or
        // `.tertiary`, which flicker as the glass sheet changes.
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
/// the row's width is the chapter. Drawn from the player's running clock
/// (`PlaybackTimeline`, once per pixel of the chapter while it plays), so
/// it's where the book is the moment it shows and lands at once on a jump,
/// a skip or From Start, rather than easing there between the player's
/// readings. A view of its own, so only the fill redraws, not the list.
/// The player's place while it has the book, else the place kept for it.
struct AudiobookChapterProgressFill: View {
    let chapter: AudiobookChapter
    let book: PlayableContent

    @Environment(\.displayScale) private var displayScale
    @State private var player = AudiobookPlayer.shared
    @State private var store = AudiobookProgressStore.shared
    @State private var width: CGFloat = 0

    private var route: PlaybackRoute { .shared }

    private func fraction(at position: TimeInterval?) -> Double {
        guard let position, chapter.duration > 0 else { return 0 }
        return min(max((position - chapter.start) / chapter.duration, 0), 1)
    }

    var body: some View {
        let isLoaded = player.isLoaded(book)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        PlaybackTimeline(
            isRunning: isLoaded && route.presented.isClockRunning,
            minimumInterval: ProgressRedraw.interval(forDuration: chapter.duration * 1000, length: width, scale: displayScale),
            position: { (isLoaded ? player.heardPosition : store.progress(for: book)?.position) ?? 0 }
        ) { position in
            Rectangle()
                .fill(Color.accent.opacity(0.25))
                .frame(width: width * fraction(at: position))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Color.accent.opacity(0.08))
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension [AudiobookChapter] {
    /// The chapter after `chapter`, for a list that leaves out the divider
    /// above the listener's chapter.
    func after(_ chapter: AudiobookChapter) -> AudiobookChapter? {
        guard let index = firstIndex(where: { $0.id == chapter.id }), index + 1 < count else { return nil }
        return self[index + 1]
    }
}
