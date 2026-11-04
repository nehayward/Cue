import SwiftUI

/// The queue toggle's glyph wherever it is (the mini player on iPad, the
/// player's bar on the Mac, the Mac window's bar): how far through the
/// queue playback is (`PresentedQueueIconView`), or for a book the bookmark
/// with its chapter's number, as a book's chapters take the panel.
struct QueueToggleIcon: View {
    var body: some View {
        if PlayerCommands.isBook {
            AudiobookChapterIconView()
        } else {
            PresentedQueueIconView()
        }
    }

    /// What the toggle does next, for its label and its tooltip.
    @MainActor
    static func title(isShown: Bool) -> String {
        if PlayerCommands.isBook {
            return isShown ? "Hide Chapters" : "Show Chapters"
        }
        return isShown ? "Hide Queue" : "Show Queue"
    }
}
