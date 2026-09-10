import XCTest
@testable import SonosKit

/// The Sonos music library's Artist order for albums, sorted here because
/// the speaker only lists albums by title.
final class LibraryAlbumSortTests: XCTestCase {
    private func album(_ title: String, by artist: String?) -> PlayableContent {
        PlayableContent(
            title: title,
            subtitle: artist ?? "",
            thumbnail: nil,
            artwork: nil,
            content: MediaContent(service: .library, id: "S://nas/\(title)", type: .album, location: nil),
            metadata: PlayableContentMetadata(artist: artist, album: title)
        )
    }

    func testOrdersByArtistThenTitle() {
        let sorted = LibraryBrowseService.sortedByArtist([
            album("Rumours", by: "Fleetwood Mac"),
            album("Tusk", by: "Fleetwood Mac"),
            album("30", by: "Adele"),
            album("Future Nostalgia", by: "Dua Lipa"),
            album("Mirage", by: "Fleetwood Mac"),
        ])
        XCTAssertEqual(sorted.map(\.title), ["30", "Future Nostalgia", "Mirage", "Rumours", "Tusk"])
    }

    func testIgnoresCaseAndAccents() {
        let sorted = LibraryBrowseService.sortedByArtist([
            album("Zebra", by: "Émilie Simon"),
            album("Alpha", by: "adele"),
            album("Beta", by: "Beyoncé"),
        ])
        XCTAssertEqual(sorted.map(\.title), ["Alpha", "Beta", "Zebra"])
    }

    func testAlbumsWithoutAnArtistFileLast() {
        let sorted = LibraryBrowseService.sortedByArtist([
            album("Unknown", by: nil),
            album("Blank", by: "  "),
            album("Known", by: "Zed"),
        ])
        XCTAssertEqual(sorted.map(\.title), ["Known", "Blank", "Unknown"])
    }

    func testDescendingReversesTheWholeOrder() {
        let ascending = LibraryBrowseService.sortedByArtist([
            album("Rumours", by: "Fleetwood Mac"),
            album("30", by: "Adele"),
            album("Tusk", by: "Fleetwood Mac"),
        ])
        let descending = LibraryBrowseService.sortedByArtist([
            album("Rumours", by: "Fleetwood Mac"),
            album("30", by: "Adele"),
            album("Tusk", by: "Fleetwood Mac"),
        ], descending: true)
        XCTAssertEqual(descending.map(\.title), ascending.map(\.title).reversed())
    }
}
