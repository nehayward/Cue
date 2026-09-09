import MusicSearchKit
import XCTest

/// The `sort` query each album order sends to Plex, and the direction each
/// one starts in.
final class PlexAlbumSortTests: XCTestCase {
    func testTitleSortsAToZFirst() {
        XCTAssertEqual(PlexAlbumSort.title.queryValue(reversed: false), "titleSort:asc")
        XCTAssertEqual(PlexAlbumSort.title.queryValue(reversed: true), "titleSort:desc")
    }

    func testArtistSortsByArtistThenTitle() {
        XCTAssertEqual(PlexAlbumSort.artist.queryValue(reversed: false), "artist.titleSort:asc,titleSort:asc")
        XCTAssertEqual(PlexAlbumSort.artist.queryValue(reversed: true), "artist.titleSort:desc,titleSort:asc")
    }

    func testDatesStartNewestFirst() {
        XCTAssertEqual(PlexAlbumSort.year.queryValue(reversed: false), "year:desc,titleSort:asc")
        XCTAssertEqual(PlexAlbumSort.year.queryValue(reversed: true), "year:asc,titleSort:asc")
        XCTAssertEqual(PlexAlbumSort.recentlyAdded.queryValue(reversed: false), "addedAt:desc,titleSort:asc")
        XCTAssertEqual(PlexAlbumSort.recentlyAdded.queryValue(reversed: true), "addedAt:asc,titleSort:asc")
    }

    func testEveryOrderHasALabelForBothDirections() {
        for sort in PlexAlbumSort.allCases {
            XCTAssertFalse(sort.label.isEmpty)
            XCTAssertNotEqual(sort.ascendingLabel, sort.descendingLabel, "\(sort) needs distinct direction labels")
        }
    }
}
