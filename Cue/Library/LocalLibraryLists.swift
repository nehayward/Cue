import SonosKit

/// The pieces of the Sonos music library's Albums and Songs lists that the
/// library's front page and its collection tabs both build — one place for
/// the sort menu and the sync status, so the screens can't drift.
@MainActor
enum LocalLibraryLists {
    /// The Albums list's sort menu. Title is the speaker's own order, paged
    /// in as before; Artist has to pull the whole list first, since the
    /// speaker only lists albums by title, then sorts it here. Both carry
    /// an A–Z index, each by the name it is ordered on.
    static func albumSortOptions(browseService: LibraryBrowseService) -> [PlayableListSort] {
        [
            PlayableListSort(
                name: "Title",
                sectionKey: { $0.title }
            ) { offset, _ in
                await browseService.albumPage(offset: offset)
            },
            PlayableListSort(
                name: "Artist",
                ascendingLabel: "A – Z",
                descendingLabel: "Z – A",
                sectionKey: { $0.metadata?.artist ?? "" }
            ) { offset, descending in
                // The whole library arrives at once, so there is no second
                // page to fetch.
                guard offset == 0 else { return [] }
                return await browseService.albumsByArtist(descending: descending)
            }
        ]
    }

    static let albumSortKey = "library.albums"

    /// The line under the Songs title: how far the one-time index sync has
    /// got while it runs, and how many tracks the library holds once it is
    /// there.
    static func songSyncStatus(browseService: LibraryBrowseService) -> () -> String? {
        {
            guard browseService.isSyncingSongs else {
                guard let count = browseService.songCount, count > 0 else { return nil }
                return count == 1 ? "1 song" : "\(count.formatted()) songs"
            }

            let synced = browseService.syncedSongCount
            guard let total = browseService.librarySongCount, total > 0 else {
                return synced == 0 ? "Loading library…" : "\(synced.formatted()) songs"
            }
            return "\(min(synced, total).formatted()) of \(total.formatted())"
        }
    }
}
