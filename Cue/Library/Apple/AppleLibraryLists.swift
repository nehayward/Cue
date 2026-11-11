import MusicSearchKit
import SonosKit
import SwiftUI

/// One of the Apple Music library's lists, pushed as
/// `RouterDestination.appleLibrary` by the library's front page and its
/// collection tabs alike, so the two can't drift.
public enum AppleLibraryList: String, Hashable, Sendable {
    case albums
    case artists
    case songs
    /// The library page's Favorites: the favorite playlists (Favorite Songs
    /// among them), albums and artists.
    case favorites

    var resource: AppleLibraryResource? {
        switch self {
        case .albums: .albums
        case .artists: .artists
        case .songs: .songs
        case .favorites: nil
        }
    }
}

/// An Apple Music library list on `PlayableListView`. Albums, Artists and
/// Songs show all of the library or only its favorites (Show, at the top of
/// the sort menu), in any order the list has (Sort By, hidden for artists,
/// which have only a name, and Order); Albums and Artists have a list or
/// grid button beside it. Each list keeps its own choices. Favorites opens
/// as a grid, newest added first.
struct AppleLibraryListScreen: View {
    let list: AppleLibraryList

    @Environment(AppleMusicBrowseService.self) private var browseService

    var body: some View {
        if let resource = list.resource {
            PlayableListView(
                title: resource.title,
                // Off, as on the other paged libraries: the index would only
                // reach the pages already loaded.
                showSectionIndex: false,
                // Songs stay rows, as in the Music app.
                allowsGrid: resource != .songs,
                layoutStorageKey: AppleLibraryLists.storageKey(list),
                filterOptions: AppleLibraryLists.filters(for: resource, browseService: browseService),
                sortStorageKey: AppleLibraryLists.storageKey(list)
            )
        } else {
            PlayableListView(
                title: "Favorites",
                showSectionIndex: false,
                allowsGrid: true,
                layoutStorageKey: AppleLibraryLists.storageKey(list),
                defaultLayout: .grid,
                sortOptions: AppleLibraryLists.favoritesShelfSortOptions(browseService: browseService),
                sortStorageKey: AppleLibraryLists.storageKey(list)
            )
        }
    }
}

/// The sort menus of the Apple Music library's lists.
@MainActor
enum AppleLibraryLists {
    /// Where a list keeps its choices. Albums' is the key its sort was
    /// kept under before it had a Show pick.
    static func storageKey(_ list: AppleLibraryList) -> String {
        "apple.\(list.rawValue)"
    }

    /// All of a kind, or only its favorites, each with the orders it has.
    static func filters(for resource: AppleLibraryResource, browseService: AppleMusicBrowseService) -> [PlayableListFilter] {
        [
            PlayableListFilter(
                name: "All \(resource.title)",
                systemImage: "square.stack",
                title: resource.title,
                sortOptions: librarySortOptions(for: resource, browseService: browseService)
            ),
            PlayableListFilter(
                name: "Favorites",
                systemImage: "star",
                title: "Favorite \(resource.title)",
                sortOptions: favoriteSortOptions(for: resource, browseService: browseService),
                emptyDescription: "\(resource.title) you favorite in Apple Music show up here.",
                favoritesOnly: true
            ),
        ]
    }

    /// All of the library. Albums and songs come in MusicKit's order, a
    /// page at a time, so every order can be flipped; a song's release
    /// date is worked out over the whole library (MusicKit can't sort songs
    /// on it). Artists come from the web API A to Z, their only order.
    private static func librarySortOptions(for resource: AppleLibraryResource, browseService: AppleMusicBrowseService) -> [PlayableListSort] {
        AppleLibrarySort.options(for: resource).map { sort in
            PlayableListSort(
                name: sort.label(for: resource),
                ascendingLabel: sort.ascendingLabel,
                descendingLabel: sort.descendingLabel,
                defaultsToDescending: sort.prefersDescending
            ) { offset, descending in
                switch resource {
                case .albums:
                    await browseService.libraryAlbums(offset: offset, sort: sort, descending: descending, marksFavorites: true)
                case .songs:
                    await browseService.librarySongs(offset: offset, sort: sort, descending: descending)
                case .artists, .playlists:
                    await browseService.libraryArtists(offset: offset, descending: descending)
                }
            }
        }
    }

    /// The favorites, read whole (they're few) and put in order here.
    private static func favoriteSortOptions(for resource: AppleLibraryResource, browseService: AppleMusicBrowseService) -> [PlayableListSort] {
        let load = { await browseService.favorites(resource) }
        return AppleLibrarySort.options(for: resource).map { sort in
            .whole(
                name: sort.label(for: resource),
                ascendingLabel: sort.ascendingLabel,
                descendingLabel: sort.descendingLabel,
                defaultsToDescending: sort.prefersDescending,
                load: load
            ) { item in
                switch sort {
                case .title: PlayableListSort.sortingKey(item.title)
                case .artist: PlayableListSort.sortingKey(item.metadata?.artist)
                case .album: PlayableListSort.sortingKey(item.metadata?.album)
                case .releaseDate: browseService.dates(of: item.id)?.released
                case .dateAdded: browseService.dates(of: item.id)?.added
                }
            }
        }
    }

    /// The library page's Favorites, newest added first by default. Apple
    /// doesn't say when something was favorited, so Date Added is when it
    /// went into the library; artists have no such date and go last.
    static func favoritesShelfSortOptions(browseService: AppleMusicBrowseService) -> [PlayableListSort] {
        let load = { await browseService.favoritesShelf() }
        return [
            .whole(
                name: "Date Added",
                ascendingLabel: "Oldest First",
                descendingLabel: "Newest First",
                defaultsToDescending: true,
                load: load
            ) { browseService.dates(of: $0.id)?.added },
            .whole(name: "Title", load: load) { PlayableListSort.sortingKey($0.title) },
            // An artist's own name, so artists sit among their albums.
            .whole(name: "Artist", load: load) {
                PlayableListSort.sortingKey($0.content.type.isArtist ? $0.title : $0.metadata?.artist)
            },
            .whole(
                name: "Release Date",
                ascendingLabel: "Oldest First",
                descendingLabel: "Newest First",
                defaultsToDescending: true,
                load: load
            ) { browseService.dates(of: $0.id)?.released },
        ]
    }
}

private extension AppleLibraryResource {
    var title: String {
        rawValue.capitalized
    }
}
