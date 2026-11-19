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

    /// A Plex song with what the library knows of it.
    private func librarySong(_ title: String, added: TimeInterval? = nil, played: TimeInterval? = nil, plays: Int? = nil, rating: Double? = nil) -> PlayableContent {
        PlayableContent(
            title: title,
            subtitle: "",
            thumbnail: nil,
            artwork: nil,
            content: MediaContent(service: .plex, id: "song:\(title)", type: .track, location: nil),
            metadata: PlayableContentMetadata(
                userRating: rating,
                addedAt: added.map { Date(timeIntervalSince1970: $0) },
                playCount: plays,
                lastPlayedAt: played.map { Date(timeIntervalSince1970: $0) }
            )
        )
    }

    func testDateAddedStartsNewestFirst() {
        let songs = [librarySong("Old", added: 100), librarySong("New", added: 300), librarySong("Middle", added: 200)]
        XCTAssertEqual(titles(songs, .dateAdded), ["New", "Middle", "Old"])
        XCTAssertEqual(titles(songs, .dateAdded, reversed: true), ["Old", "Middle", "New"])
    }

    func testLastPlayedPutsSongsNeverPlayedLastEitherWay() {
        let songs = [librarySong("Never"), librarySong("Yesterday", played: 200), librarySong("Today", played: 300)]
        XCTAssertEqual(titles(songs, .lastPlayed), ["Today", "Yesterday", "Never"])
        XCTAssertEqual(titles(songs, .lastPlayed, reversed: true), ["Yesterday", "Today", "Never"])
    }

    func testPlayCountStartsMostPlayedAndKeepsPlaylistOrderForTies() {
        let songs = [librarySong("Once", plays: 1), librarySong("Never A", plays: 0), librarySong("Often", plays: 12), librarySong("Never B", plays: 0)]
        XCTAssertEqual(titles(songs, .playCount), ["Often", "Once", "Never A", "Never B"])
        XCTAssertEqual(titles(songs, .playCount, reversed: true), ["Never A", "Never B", "Once", "Often"])
    }

    func testRatingPutsUnratedSongsLastEitherWay() {
        // Plex's 0 is no rating, as is none at all.
        let songs = [librarySong("Unrated"), librarySong("Three Stars", rating: 6), librarySong("Zero", rating: 0), librarySong("Five Stars", rating: 10)]
        XCTAssertEqual(titles(songs, .rating), ["Five Stars", "Three Stars", "Unrated", "Zero"])
        XCTAssertEqual(titles(songs, .rating, reversed: true), ["Three Stars", "Five Stars", "Unrated", "Zero"])
    }

    func testLibraryOrdersAreOfferedOnlyWhereSongsCarryThem() {
        XCTAssertEqual(PlaylistSongSort.options(withLibraryDetails: true), PlaylistSongSort.allCases)
        XCTAssertEqual(PlaylistSongSort.options(withLibraryDetails: false), [.playlistOrder, .title, .artist, .album, .duration])
    }
}
