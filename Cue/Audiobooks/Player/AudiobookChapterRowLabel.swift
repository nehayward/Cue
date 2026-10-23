import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// A chapter's row: a bookmark, its title, where it starts and how long it
/// runs. `isHere` marks the listener's chapter, in the accent; `isDone` one
/// before their place, its bookmark filled and its title dimmed, so the
/// list reads as how far the book has got. The book's page and the
/// chapters sheet both list them so.
struct AudiobookChapterRowLabel: View {
    let chapter: AudiobookChapter
    let isHere: Bool
    var isDone = false

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
        .contentShape(.rect)
    }
}
