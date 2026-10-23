import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// The player's origin line while a book with chapters plays: the chapter
/// playing, in the caption slot the album or playlist has for a song, and
/// a tap opens the chapters sheet (`AudiobookChaptersView`). It reads the
/// chapter, which changes only at a chapter's end, so it's a view of its
/// own: the player around it doesn't redraw with it.
struct AudiobookChapterLine: View {
    @Environment(Router.self) private var router
    @State private var player = AudiobookPlayer.shared

    var body: some View {
        Button {
            HapticManager.shared.fireHaptic(.selection)
            router.sheet(to: .audiobookChapters)
        } label: {
            Text(player.currentChapter?.title ?? "")
            .font(.caption.smallCaps())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .contentTransition(.identity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chapter: \(player.currentChapter?.title ?? "")")
        .accessibilityHint("Shows the chapters")
    }
}
