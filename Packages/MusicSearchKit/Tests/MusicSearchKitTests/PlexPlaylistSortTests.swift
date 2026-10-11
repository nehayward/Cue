import MusicSearchKit
import XCTest

/// The `sort` query each playlist order sends to Plex, and the direction
/// each one starts in.
final class PlexPlaylistSortTests: XCTestCase {
    func testTitleSortsAToZFirst() {
        XCTAssertEqual(PlexPlaylistSort.title.queryValue(reversed: false), "titleSort:asc")
        XCTAssertEqual(PlexPlaylistSort.title.queryValue(reversed: true), "titleSort:desc")
    }

    func testDatesStartNewestFirst() {
        XCTAssertEqual(PlexPlaylistSort.dateAdded.queryValue(reversed: false), "addedAt:desc,titleSort:asc")
        XCTAssertEqual(PlexPlaylistSort.dateAdded.queryValue(reversed: true), "addedAt:asc,titleSort:asc")
        XCTAssertEqual(PlexPlaylistSort.lastPlayed.queryValue(reversed: false), "lastViewedAt:desc,titleSort:asc")
        XCTAssertEqual(PlexPlaylistSort.lastPlayed.queryValue(reversed: true), "lastViewedAt:asc,titleSort:asc")
    }

    func testCountsStartBiggestFirst() {
        XCTAssertEqual(PlexPlaylistSort.playCount.queryValue(reversed: false), "viewCount:desc,titleSort:asc")
        XCTAssertEqual(PlexPlaylistSort.duration.queryValue(reversed: false), "duration:desc,titleSort:asc")
        XCTAssertEqual(PlexPlaylistSort.songCount.queryValue(reversed: false), "leafCount:desc,titleSort:asc")
        XCTAssertEqual(PlexPlaylistSort.songCount.queryValue(reversed: true), "leafCount:asc,titleSort:asc")
    }

    func testEveryOrderHasALabelForBothDirections() {
        for sort in PlexPlaylistSort.allCases {
            XCTAssertFalse(sort.label.isEmpty)
            XCTAssertNotEqual(sort.ascendingLabel, sort.descendingLabel, "\(sort) needs distinct direction labels")
        }
    }
}
