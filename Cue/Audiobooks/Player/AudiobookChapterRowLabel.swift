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
                .foregroundStyle(isHere ? AnyShapeStyle(.primary) : isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .foregroundStyle(isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .fontWeight(isHere ? .semibold : .regular)
                Text(AudiobookFormat.clock(chapter.start))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Text(AudiobookFormat.duration(chapter.duration))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // The listener's chapter is the accent throughout: its levels
        // (primary, secondary) are the accent's.
        .foregroundStyle(isHere ? AnyShapeStyle(.tint) : AnyShapeStyle(.foreground))
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}
