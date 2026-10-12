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
    }

    /// Plex won't sort playlists by `leafCount`, so Song Count asks for A–Z
    /// and orders the sizes itself.
    func testSongCountAsksForTitleOrder() {
        XCTAssertEqual(PlexPlaylistSort.songCount.queryValue(reversed: false), "titleSort:asc")
        XCTAssertEqual(PlexPlaylistSort.songCount.queryValue(reversed: true), "titleSort:asc")
    }

    func testSongCountSortsBiggestFirstKeepingTitleOrderForTies() throws {
        let playlists = try decode([("Alpha", 3), ("Bravo", 12), ("Charlie", nil), ("Delta", 3)])

        let biggest = PlexPlaylistSort.songCount.sort(playlists).map(\.title)
        XCTAssertEqual(biggest, ["Bravo", "Alpha", "Delta", "Charlie"])

        let smallest = PlexPlaylistSort.songCount.sort(playlists, reversed: true).map(\.title)
        XCTAssertEqual(smallest, ["Charlie", "Alpha", "Delta", "Bravo"])
    }

    func testServerOrdersPassThrough() throws {
        let playlists = try decode([("Bravo", 1), ("Alpha", 9)])
        XCTAssertEqual(PlexPlaylistSort.dateAdded.sort(playlists).map(\.title), ["Bravo", "Alpha"])
    }

    /// Playlists as `/playlists` sends them: a title and, for most, a count.
    private func decode(_ playlists: [(title: String, songs: Int?)]) throws -> [PlexUserPlaylist] {
        let json = playlists.enumerated().map { index, playlist in
            var object: [String: Any] = ["ratingKey": "\(index)", "title": playlist.title]
            if let songs = playlist.songs { object["leafCount"] = songs }
            return object
        }
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode([PlexUserPlaylist].self, from: data)
    }

    func testEveryOrderHasALabelForBothDirections() {
        for sort in PlexPlaylistSort.allCases {
            XCTAssertFalse(sort.label.isEmpty)
            XCTAssertNotEqual(sort.ascendingLabel, sort.descendingLabel, "\(sort) needs distinct direction labels")
        }
    }
}
