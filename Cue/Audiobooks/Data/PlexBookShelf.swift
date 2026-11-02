import Defaults
import Foundation
import MusicSearchKit
import SonosKit

/// Plex's books for the Audiobooks tab: its newest, for the Plex shelf, and
/// all of them, for the Series shelf. A store rather than the tab's own
/// state so it starts out holding the last read kept
/// (`AudiobookLibrary.cachedPlexBooksAndNewest()`): the tab's first frame
/// has the books, where state filled in its `.task` showed placeholders
/// for a frame or more first. The server is read behind it (`read(tries:)`).
@MainActor
@Observable
final class PlexBookShelf {
    static let shared = PlexBookShelf()

    /// The books added last, newest first.
    private(set) var newest: [PlayableContent] = []
    /// Every book.
    private(set) var all: [PlayableContent] = []
    /// While the server is read with nothing kept to show: the shelf keeps
    /// its room. True from the first frame, before Plex is first asked
    /// whether it has books.
    private(set) var isLoading = true
    /// Plex didn't answer after a few tries, with nothing kept to show.
    private(set) var failed = false
    /// Read from the server since launch, or since the server last changed.
    private(set) var isFresh = false
    /// The server these are from.
    private var server: String?
    /// Whether the Plex server has books (`AppStorageKeys.hasPlexAudiobooks`),
    /// kept here for the Audiobooks tab to observe. Held there in
    /// `@AppStorage`, the tab rebuilt with every UserDefaults write, shown
    /// or not. `AudiobookLibrary.checkPlexBooks` sets both.
    var hasBooks = UserDefaults.standard.bool(forKey: AppStorageKeys.hasPlexAudiobooks)

    private init() {
        show(server: MusicSearchService.shared.plexServerID)
    }

    /// Shows `server`'s books as last read, when it isn't the one shown:
    /// another server's books aren't this one's. Nothing is asked of
    /// Audible here: this also runs at launch (the covers decoded ahead),
    /// and the tab asks as it shows (`AudiobooksScreen`).
    func show(server: String?) {
        guard server != self.server || (newest.isEmpty && all.isEmpty) else { return }
        self.server = server
        let kept = AudiobookLibrary.cachedPlexBooksAndNewest()
        newest = kept?.newest ?? []
        all = kept?.all ?? []
        isFresh = false
        if kept != nil {
            isLoading = false
        }
    }

    /// Reads the server. A read that fails is tried again after a pause: as
    /// the tab first shows, the server's connection is often still being
    /// found, and one miss left the row empty until a pull. What's shown
    /// stays when every try fails.
    func read(tries: Int) async {
        isLoading = newest.isEmpty
        failed = false
        for attempt in 1...tries {
            let read = await AudiobookLibrary.plexBooksAndNewest()
            // Put away (another server, the tab left): a cancelled read
            // fails or comes back short, and isn't the answer.
            guard !Task.isCancelled else { return }
            if let read {
                newest = read.newest
                all = read.all
                isFresh = true
                isLoading = false
                AudiobookDetails.shared.request(read.all)
                return
            }
            AudiobookLibrary.log.info("plex shelf: newest books not read, try \(attempt) of \(tries)")
            if attempt < tries {
                guard (try? await Task.sleep(for: .seconds(2 * attempt))) != nil else { return }
            }
        }
        isLoading = false
        failed = newest.isEmpty
    }
}
