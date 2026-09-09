import MusicSearchKit
import SonosKit

/// The pieces of the Apple Music library's Albums list that the library's
/// front page and the Albums tab both build — one place for the sort menu,
/// so the two screens can't drift.
@MainActor
enum AppleLibraryLists {
    /// The Albums list's sort menu. Every order comes from MusicKit's index
    /// of the library, so each page arrives already sorted and every order
    /// can be flipped.
    static func albumSortOptions(browseService: AppleMusicBrowseService) -> [PlayableListSort] {
        AppleLibraryAlbumSort.allCases.map { sort in
            PlayableListSort(
                name: sort.label,
                ascendingLabel: sort.ascendingLabel,
                descendingLabel: sort.descendingLabel,
                defaultsToDescending: sort.prefersDescending
            ) { offset, descending in
                await browseService.libraryAlbums(offset: offset, sort: sort, descending: descending)
            }
        }
    }

    static let albumSortKey = "apple.albums"
}
