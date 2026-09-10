import MusicSearchKit
import SonosKit

/// The pieces of Plex's Songs list that the library's front page and the
/// Songs tab both build — one place for the sort menu and the sync status,
/// so the two screens can't drift.
@MainActor
enum PlexLibraryLists {
    /// The Songs list's sort menu. Every option is a Plex `sort` field, so
    /// the server does the ordering and each page comes back already in it —
    /// no local copy of the library, and reversing works on the whole list
    /// rather than the page in front of you.
    static func songSortOptions(musicSearchService: MusicSearchService) -> [PlayableListSort] {
        PlexSongSort.allCases.map { sort in
            PlayableListSort(
                name: sort.label,
                // Nil for an order with no meaningful opposite, which is
                // how the menu knows to leave the direction picker out.
                ascendingLabel: sort.isReversible ? sort.ascendingLabel : nil,
                descendingLabel: sort.isReversible ? sort.descendingLabel : nil
            ) { offset, reversed in
                await musicSearchService.plexSongs(offset: offset, sort: sort, reversed: reversed)
            }
        }
    }

    /// The Albums list's sort menu. Plex sorts albums on the server as it
    /// does songs, so every order pages in already sorted and every one
    /// can be flipped.
    static func albumSortOptions(plexBrowseService: PlexBrowseService) -> [PlayableListSort] {
        PlexAlbumSort.allCases.map { sort in
            PlayableListSort(
                name: sort.label,
                ascendingLabel: sort.ascendingLabel,
                descendingLabel: sort.descendingLabel
            ) { offset, reversed in
                await plexBrowseService.updateUserAlbums(offset: offset, sort: sort, reversed: reversed)
            }
        }
    }

    /// The line under the Songs title: how far the one-time library sync has
    /// got while it runs, and how big the library is once it is there.
    static func songSyncStatus(musicSearchService: MusicSearchService) -> () -> String? {
        {
            guard musicSearchService.isSyncingPlexSongs else {
                guard let count = musicSearchService.plexSongCount, count > 0 else { return nil }
                return count == 1 ? "1 song" : "\(count.formatted()) songs"
            }

            let synced = musicSearchService.plexSyncedSongCount
            guard let total = musicSearchService.plexLibrarySongCount, total > 0 else {
                return synced == 0 ? "Loading library…" : "\(synced.formatted()) songs"
            }
            return "\(min(synced, total).formatted()) of \(total.formatted())"
        }
    }

    /// The Songs list's storage key for its remembered sort. Named, because
    /// Subsonic has a "Songs" too.
    static let songSortKey = "plex.songs"
    static let albumSortKey = "plex.albums"
}
