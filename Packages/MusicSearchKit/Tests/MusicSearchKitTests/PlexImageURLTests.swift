import MusicSearchKit
import XCTest

final class PlexImageURLTests: XCTestCase {
    func testThumbIsRoutedThroughTheTranscoder() throws {
        let url = try XCTUnwrap(URL(string: "http://192.168.1.10:32400/library/metadata/123/thumb/456?X-Plex-Token=abc"))
        let resized = try XCTUnwrap(URLComponents(url: url.plexResized(to: 300), resolvingAgainstBaseURL: false))

        XCTAssertEqual(resized.host, "192.168.1.10")
        XCTAssertEqual(resized.port, 32400)
        XCTAssertEqual(resized.path, "/photo/:/transcode")
        let query = Dictionary(uniqueKeysWithValues: (resized.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(query["width"], "300")
        XCTAssertEqual(query["height"], "300")
        XCTAssertEqual(query["minSize"], "1")
        XCTAssertEqual(query["upscale"], "0")
        XCTAssertEqual(query["url"], "/library/metadata/123/thumb/456")
        XCTAssertEqual(query["X-Plex-Token"], "abc")
    }

    func testPlaylistCompositeIsRoutedThroughTheTranscoder() throws {
        let url = try XCTUnwrap(URL(string: "https://plex.example.com/playlists/9/composite/1?X-Plex-Token=abc"))
        let resized = try XCTUnwrap(URLComponents(url: url.plexResized(to: 1200), resolvingAgainstBaseURL: false))

        XCTAssertEqual(resized.path, "/photo/:/transcode")
        XCTAssertEqual(resized.queryItems?.first { $0.name == "url" }?.value, "/playlists/9/composite/1")
    }

    func testReverseProxyPrefixStaysInFrontOfTheTranscoder() throws {
        let url = try XCTUnwrap(URL(string: "https://home.example.com/plex/library/metadata/1/thumb/2?X-Plex-Token=abc"))
        let resized = try XCTUnwrap(URLComponents(url: url.plexResized(to: 300), resolvingAgainstBaseURL: false))

        XCTAssertEqual(resized.path, "/plex/photo/:/transcode")
        XCTAssertEqual(resized.queryItems?.first { $0.name == "url" }?.value, "/library/metadata/1/thumb/2")
    }

    func testAlreadyResizedAndForeignURLsAreLeftAlone() throws {
        let transcode = try XCTUnwrap(URL(string: "http://h:32400/photo/:/transcode?width=300&url=/library/metadata/1/thumb/2&X-Plex-Token=abc"))
        XCTAssertEqual(transcode.plexResized(to: 1200), transcode)

        let noToken = try XCTUnwrap(URL(string: "http://h:32400/library/metadata/1/thumb/2"))
        XCTAssertEqual(noToken.plexResized(to: 300), noToken)

        let apple = try XCTUnwrap(URL(string: "https://is1-ssl.mzstatic.com/image/thumb/a.jpg/600x600bb.jpg"))
        XCTAssertEqual(apple.plexResized(to: 300), apple)
    }
}
