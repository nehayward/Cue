import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// What's left of the chapter playing, "33m left in chapter", or of the
/// whole book, "14h 24m left in book", after `prefix` (the author, or the
/// speaker) when there is one: the player's middle line for a book, in the
/// audio quality's place, and the mini player's line under the title. A
/// tap on the player's switches the two, for the mini player's too. It
/// reads the book's place, which moves every couple of seconds, so it's a
/// view of its own: the player around it doesn't redraw with it.
struct AudiobookTimeLeft: View {
    var prefix: String? = nil
    /// "33m left", for a narrow line (the mini player's), which leaves a
    /// tap to the mini player.
    var isCompact = false

    @State private var player = AudiobookPlayer.shared
    @AppStorage(AppStorageKeys.audiobookTimeLeftShowsBook) private var showsBook = false

    var body: some View {
        let left = player.timeLeftText(ofBook: showsBook, compact: isCompact)
        let parts = [prefix.flatMap { $0.isEmpty ? nil : $0 }, left].compactMap { $0 }
        let line = Text(parts.joined(separator: " • "))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.default, value: left)
        if !isCompact, player.hasChapters {
            Button {
                HapticManager.shared.fireHaptic(.selection)
                showsBook.toggle()
            } label: {
                line
                    // A caption is a small target: take a little more
                    // around it, short of the scrubber above.
                    .contentShape(Rectangle().inset(by: -6))
            }
            .buttonStyle(.plain)
            .accessibilityHint(showsBook ? "Shows the time left in the chapter" : "Shows the time left in the book")
        } else {
            line
        }
    }
}
