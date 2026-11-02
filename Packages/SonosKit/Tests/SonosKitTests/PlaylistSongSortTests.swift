import XCTest
@testable import SonosKit

/// The orders a playlist's songs can be listed in, put together in the app
/// because Plex keeps a playlist in its own order.
final class PlaylistSongSortTests: XCTestCase {
    private func song(_ title: String, by artist: String? = nil, on album: String? = nil, seconds: Int64? = nil) -> PlayableContent {
        PlayableContent(
            title: title,
            subtitle: artist ?? "",
            thumbnail: nil,
            artwork: nil,
            content: MediaContent(service: .plex, id: "song:\(title)", type: .track, location: nil),
            metadata: PlayableContentMetadata(duration: seconds.map { .seconds($0) }, artist: artist, album: album)
        )
    }

    private func titles(_ songs: [PlayableContent], _ sort: PlaylistSongSort, reversed: Bool = false) -> [String] {
        sort.order(of: songs, reversed: reversed).map { songs[$0].title }
    }

    func testPlaylistOrderLeavesTheSongsWhereTheyAre() {
        let songs = [song("Zebra"), song("Alpha"), song("Mango")]
        XCTAssertEqual(titles(songs, .playlistOrder), ["Zebra", "Alpha", "Mango"])
        XCTAssertEqual(titles(songs, .playlistOrder, reversed: true), ["Zebra", "Alpha", "Mango"])
    }

    func testTitleSortsAToZAndFlips() {
        let songs = [song("zebra"), song("Alpha"), song("Track 10"), song("Track 2")]
        XCTAssertEqual(titles(songs, .title), ["Alpha", "Track 2", "Track 10", "zebra"])
        XCTAssertEqual(titles(songs, .title, reversed: true), ["zebra", "Track 10", "Track 2", "Alpha"])
    }

    func testArtistGroupsAlbumsAndKeepsPlaylistOrderWithinThem() {
        let songs = [
            song("Dreams", by: "Fleetwood Mac", on: "Rumours"),
            song("Hello", by: "Adele", on: "25"),
            song("Sara", by: "Fleetwood Mac", on: "Tusk"),
            song("Go Your Own Way", by: "Fleetwood Mac", on: "Rumours"),
        ]
        XCTAssertEqual(titles(songs, .artist), ["Hello", "Dreams", "Go Your Own Way", "Sara"])
    }

    func testMissingValuesGoLastEitherWay() {
        let songs = [song("Unknown"), song("Hello", by: "Adele"), song("Halo", by: "Beyoncé")]
        XCTAssertEqual(titles(songs, .artist), ["Hello", "Halo", "Unknown"])
        XCTAssertEqual(titles(songs, .artist, reversed: true), ["Halo", "Hello", "Unknown"])
    }

    func testDurationStartsLongestFirst() {
        let songs = [song("Short", seconds: 120), song("Long", seconds: 600), song("None"), song("Middle", seconds: 240)]
        XCTAssertEqual(titles(songs, .duration), ["Long", "Middle", "Short", "None"])
        XCTAssertEqual(titles(songs, .duration, reversed: true), ["Short", "Middle", "Long", "None"])
    }

    func testOnlyPlaylistOrderCantBeFlipped() {
        for sort in PlaylistSongSort.allCases {
            XCTAssertEqual(sort.isReversible, sort != .playlistOrder)
            XCTAssertFalse(sort.label.isEmpty)
        }
    }
}
