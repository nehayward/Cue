import XCTest
@testable import WatchSync

final class WatchBrowseTests: XCTestCase {
    private let artist = WatchContentRef(source: .subsonic, kind: .artist, id: "ar-1", title: "Artist", subtitle: "", artworkURL: nil)

    func testRequestsRoundTrip() throws {
        let requests: [WatchRequest] = [
            .browse(.root, offset: 0),
            .browse(.source(.plex), offset: 0),
            .browse(.section(.subsonic, .recentlyAdded), offset: 40),
            .browse(.artist(artist), offset: 0),
            .add(artist, quality: nil),
            .add(artist, quality: .small),
            .remove(artist),
        ]
        for request in requests {
            XCTAssertEqual(try WatchRequest.decoded(from: request.encoded()), request)
        }
    }

    func testRepliesRoundTrip() throws {
        let item = WatchBrowseItem(id: "a", title: "Album", subtitle: "Artist", content: artist, collectionKey: "artist-subsonic-ar-1")
        let page = WatchBrowsePage(title: "Albums", items: [item], nextOffset: 40, container: item, message: nil)
        guard case let .page(decoded) = try WatchReply.decoded(from: WatchReply.page(page).encoded()) else {
            return XCTFail("Expected a page")
        }
        XCTAssertEqual(decoded.items, [item])
        XCTAssertEqual(decoded.nextOffset, 40)
        XCTAssertEqual(decoded.container, item)

        guard case .added(songs: 12) = try WatchReply.decoded(from: WatchReply.added(songs: 12).encoded()) else {
            return XCTFail("Expected added")
        }
        guard case .needsQuality = try WatchReply.decoded(from: WatchReply.needsQuality.encoded()) else {
            return XCTFail("Expected needsQuality")
        }
    }

    func testAFullPageFitsInAMessage() throws {
        let items = (0 ..< WatchReply.pageSize).map { index in
            let ref = WatchContentRef(
                source: .plex,
                kind: .album,
                id: "2b5d1c0f9a8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c%3A3%3A\(100_000 + index)",
                title: "A Fairly Long Album Title Number \(index) (Deluxe Edition)",
                subtitle: "Some Artist With A Long Name",
                artworkURL: URL(string: "https://192-168-1-20.0123456789abcdef0123456789abcdef.plex.direct:32400/photo/:/transcode?width=600&height=600&url=%2Flibrary%2Fmetadata%2F\(index)%2Fthumb%2F1700000000&X-Plex-Token=abcdefghijklmnopqrst")
            )
            return WatchBrowseItem(id: ref.id, title: ref.title, subtitle: ref.subtitle, artworkURL: ref.artworkURL, content: ref, collectionKey: "album-\(ref.id)")
        }
        let data = try WatchReply.page(WatchBrowsePage(title: "Albums", items: items, nextOffset: 40)).encoded()
        XCTAssertLessThan(data.count, 60_000)
    }

    func testQualitiesSayWhatTheyCost() {
        XCTAssertEqual(WatchDownloadQuality.high.megabytesPerSong, 8)
        XCTAssertEqual(WatchDownloadQuality.medium.megabytesPerSong, 6)
        XCTAssertEqual(WatchDownloadQuality.small.megabytesPerSong, 4)
        XCTAssertNil(WatchDownloadQuality.original.bitrate)
        XCTAssertEqual(WatchDownloadQuality.small.detail, "MP3 128 kbps • about 4 MB a song")
    }
}
