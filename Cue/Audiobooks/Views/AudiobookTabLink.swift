import Foundation
import Observation
import SonosKit

/// Opens a book's page in the Audiobooks tab from outside it: the book
/// shelf widget's Open Book, a `cue://audiobook` link. On the tab's own
/// stack, so Back goes to the tab, rather than a page presented over
/// everything, which each tap stacked another of. The tab keeps a router
/// of its own (`AudiobooksScreen`), which nothing outside it can push on,
/// so this holds the request and the tab's screen pushes the page on its
/// own stack and clears it.
@MainActor
@Observable
final class AudiobookTabLink {
    static let shared = AudiobookTabLink()

    struct Request {
        /// New for each request, so the same book asked for again opens again.
        let id = UUID()
        let book: PlayableContent
    }

    var request: Request?

    private init() {}

    /// `book`'s page in the Audiobooks tab; while the tab is hidden
    /// (Settings ▸ Appearance), over whatever is on screen.
    func open(_ book: PlayableContent) {
        guard AppState.shared.showsAudiobooksTab else {
            MediaDetailPresenter.present(book)
            return
        }
        Self.showTab()
        request = Request(book: book)
    }

    /// The Audiobooks tab, with the player and any page presented over the
    /// tabs put away.
    static func showTab() {
        Router.main.isPlayerPresented = false
        MediaDetailPresenter.dismissPresented()
        Router.main.selectedTab = .audiobooks
    }
}
