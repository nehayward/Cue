import Defaults
import MusicSearchKit
import SonosKit

/// The pieces of Subsonic's lists that the library's front page and the
/// collection tabs both build — one place for the sort menus and the sync
/// status, so the screens can't drift.
@MainActor
enum SubsonicLibraryLists {
    /// The Artists list's menu: every artist, or only the starred ones.
    /// `getArtists` has no order to choose, so that's all there is to pick.
    static func artistSortOptions(musicSearchService: MusicSearchService) -> [PlayableListSort] {
        [
            PlayableListSort(name: "Name") { offset, _ in
                await musicSearchService.subsonicArtists(offset: offset)
            },
            PlayableListSort(name: "Favorites") { offset, _ in
                await musicSearchService.subsonicFavoriteArtists(offset: offset)
            },
        ]
    }

    /// The Favorites list's orders: the artists, albums and songs starred on
    /// the server, read whole with one `getStarred2` each time the list
    /// opens or is pulled, and ordered here (`LocalSorts`).
    static func favoriteSortOptions(musicSearchService: MusicSearchService) -> [PlayableListSort] {
        let favorites = LocalSorts { await musicSearchService.subsonicFavorites() }
        return [
            favorites.byDate("Date Favorited") { musicSearchService.subsonicFavoriteDate(of: $0.id) },
            favorites.byName("Title") { $0.title },
            // An artist's own name, so artists sit among their albums.
            favorites.byName("Artist") { $0.content.type.isArtist ? $0.title : $0.metadata?.artist },
        ]
    }

    /// The Favorites list: a grid at first, its layout its own
    /// (`AppStorageKeys.subsonicFavoritesLayout`) since it mixes artists,
    /// albums and songs, with a pull that reads the server again.
    static func favoritesDestination(musicSearchService: MusicSearchService) -> RouterDestination {
        .playableList(
            title: "Favorites",
            showSectionIndex: false,
            allowsGrid: true,
            layoutKey: AppStorageKeys.subsonicFavoritesLayout,
            sortOptions: favoriteSortOptions(musicSearchService: musicSearchService),
            sortKey: favoritesSortKey,
            // Nothing to do first: the list's reload is the read.
            refreshAction: {}
        )
    }

    /// The Songs list's sort menu. Sorting happens on the synced copy of the
    /// library rather than on the server, which has no sort for songs.
    static func songSortOptions(musicSearchService: MusicSearchService) -> [PlayableListSort] {
        SubsonicSongSort.allCases.map { sort in
            PlayableListSort(
                name: sort.label,
                // Nil for an order with no meaningful opposite, which is
                // how the menu knows to leave the direction picker out.
                ascendingLabel: sort.isReversible ? sort.ascendingLabel : nil,
                descendingLabel: sort.isReversible ? sort.descendingLabel : nil
            ) { offset, descending in
                await musicSearchService.subsonicSongs(offset: offset, sort: sort, descending: descending)
            }
        }
    }

    /// The Albums list's sort menu — these orders the server does provide, so
    /// each one is just a different `getAlbumList2` list type. No direction
    /// toggle: the list pages, and reversing a page is not reversing a list.
    static func albumSortOptions(musicSearchService: MusicSearchService) -> [PlayableListSort] {
        SubsonicAlbumSort.allCases.map { sort in
            PlayableListSort(name: sort.label) { offset, _ in
                await musicSearchService.subsonicAlbums(offset: offset, sort: sort)
            }
        }
    }

    /// The line under the Songs title: how far the one-time library sync has
    /// got while it runs, and how big the library is once it is there. Songs
    /// is the only list that pulls the whole library in before it can show a
    /// row, so it is the only one that owes the user a count.
    static func songSyncStatus(musicSearchService: MusicSearchService) -> () -> String? {
        {
            guard musicSearchService.isSyncingSubsonicSongs else {
                guard let count = musicSearchService.subsonicSongCount, count > 0 else { return nil }
                return count == 1 ? "1 song" : "\(count.formatted()) songs"
            }

            let synced = musicSearchService.subsonicSyncedSongCount
            guard let total = musicSearchService.subsonicLibrarySongCount, total > 0 else {
                // No total: the server won't report one, so a running count
                // is all there is to say.
                return synced == 0 ? "Loading library…" : "\(synced.formatted()) songs"
            }
            return "\(min(synced, total).formatted()) of \(total.formatted())"
        }
    }

    /// The pull to refresh on the lists read straight from the server —
    /// Artists, Albums, Recently Added. They keep no copy, so the pull's
    /// reload of the first page is what brings in an album added on the
    /// server; this only checks whether the library's size changed, so Songs
    /// re-syncs on its next open too.
    static func serverListRefresh(musicSearchService: MusicSearchService) -> () async -> Void {
        { await musicSearchService.refreshSubsonicLibraryIfChanged() }
    }

    static let songSortKey = "subsonic.songs"
    static let albumSortKey = "subsonic.albums"
    static let artistSortKey = "subsonic.artists"
    static let favoritesSortKey = "subsonic.favorites"
}
