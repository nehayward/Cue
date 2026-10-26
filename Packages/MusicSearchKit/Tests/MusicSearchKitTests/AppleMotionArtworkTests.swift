import MusicSearchKit
import XCTest

final class AppleMotionArtworkTests: XCTestCase {
    private func response(_ attributes: String) -> Data {
        Data("""
        {"data":[{"id":"1649434004","type":"albums","attributes":{"name":"Midnights"\(attributes)}}]}
        """.utf8)
    }

    func testReadsEveryShapesVideo() throws {
        let data = response("""
        ,"editorialVideo":{
          "motionDetailSquare":{"previewFrame":{"url":"https://a/{w}x{h}bb.{f}","width":3840,"height":3840},"video":"https://mvod.example/square.m3u8"},
          "motionDetailTall":{"previewFrame":{"url":"https://a/{w}x{h}bb.{f}"},"video":"https://mvod.example/tall.m3u8"}
        }
        """)
        let videos = try XCTUnwrap(AppleMotionArtwork.editorialVideos(inAlbumResponse: data))

        XCTAssertEqual(videos["motionDetailSquare"]?.absoluteString, "https://mvod.example/square.m3u8")
        XCTAssertEqual(videos["motionDetailTall"]?.absoluteString, "https://mvod.example/tall.m3u8")
    }

    func testNoEditorialVideoIsNil() throws {
        XCTAssertNil(try AppleMotionArtwork.editorialVideos(inAlbumResponse: response("")))
    }

    func testAShapeWithoutAVideoIsLeftOutNotFailed() throws {
        let data = response("""
        ,"editorialVideo":{"motionDetailSquare":{"previewFrame":{}},"motionSquareVideo1x1":"odd","motionDetailTall":{"video":"https://mvod.example/tall.m3u8"}}
        """)
        let videos = try XCTUnwrap(AppleMotionArtwork.editorialVideos(inAlbumResponse: data))

        XCTAssertEqual(Array(videos.keys), ["motionDetailTall"])
    }

    /// An album page laid out as music.apple.com's: its header section, then
    /// `sections` after it.
    private func page(header: String, sections: String = "") -> Data {
        Data("""
        <!DOCTYPE html><html><head><script type="module" src="/assets/index.js"></script></head><body>
        <script type="application/json" id="serialized-server-data">{"data":[{"intent":{"$kind":"AlbumDetailPageIntent"},"data":{"sections":[\
        {"id":"album-detail-header-section - 1499378108","itemKind":"containerDetailHeaderLockup","items":[{"title":"After Hours"\(header)}]}\(sections)\
        ]}}],"userTokenHash":"x"}</script>
        <script>window.x = 1;</script></body></html>
        """.utf8)
    }

    func testReadsTheAlbumPagesHeaderVideos() throws {
        let data = page(header: """
        ,"videoArtwork":{"dictionary":{"motionDetailSquare":{"previewFrame":{"url":"https://a/{w}x{h}bb.{f}","height":3840},"video":"https://mvod.example/square.m3u8"}}},\
        "tallVideoArtwork":{"dictionary":{"motionDetailTall":{"previewFrame":{"url":"https://a/{w}x{h}bb.{f}"},"video":"https://mvod.example/tall.m3u8"}}}
        """)
        let videos = try XCTUnwrap(AppleMotionArtwork.editorialVideos(inAlbumPage: data))
        let artwork = try XCTUnwrap(AppleMotionArtwork(videos: videos))

        XCTAssertEqual(artwork.square?.absoluteString, "https://mvod.example/square.m3u8")
        XCTAssertEqual(artwork.tall?.absoluteString, "https://mvod.example/tall.m3u8")
    }

    func testAnotherAlbumsVideoFurtherDownThePageIsIgnored() throws {
        let data = page(header: "", sections: """
        ,{"id":"more-by-artist","itemKind":"squareLockup","items":["odd",{"title":"Dawn FM","videoArtwork":{"dictionary":{"motionDetailSquare":{"video":"https://mvod.example/other.m3u8"}}}}]}
        """)

        XCTAssertEqual(try AppleMotionArtwork.editorialVideos(inAlbumPage: data), [:])
    }

    func testAPageWithoutItsDataIsNil() throws {
        let html = Data("<html><body><h1>Album</h1></body></html>".utf8)

        XCTAssertNil(try AppleMotionArtwork.editorialVideos(inAlbumPage: html))
    }

    func testPrefersTheAlbumPagesShapes() throws {
        let artwork = try XCTUnwrap(AppleMotionArtwork(videos: [
            "motionSquareVideo1x1": URL(string: "https://v/grid-square.m3u8")!,
            "motionDetailSquare": URL(string: "https://v/page-square.m3u8")!,
            "motionTallVideo3x4": URL(string: "https://v/grid-tall.m3u8")!,
        ]))

        XCTAssertEqual(artwork.square?.lastPathComponent, "page-square.m3u8")
        XCTAssertEqual(artwork.tall?.lastPathComponent, "grid-tall.m3u8")
    }

    func testAnUnknownNameThatSaysItsShapeStillCounts() throws {
        let artwork = try XCTUnwrap(AppleMotionArtwork(videos: ["motionWideSquare": URL(string: "https://v/s.m3u8")!]))

        XCTAssertEqual(artwork.square?.lastPathComponent, "s.m3u8")
        XCTAssertNil(artwork.tall)
    }

    func testNoShapeIsNoArtwork() {
        XCTAssertNil(AppleMotionArtwork(videos: [:]))
        XCTAssertNil(AppleMotionArtwork(videos: ["motionWide16x9": URL(string: "https://v/w.m3u8")!]))
    }

    func testFallsBackToTheOtherShape() {
        let squareOnly = AppleMotionArtwork(square: URL(string: "https://v/s.m3u8"), tall: nil)
        let tallOnly = AppleMotionArtwork(square: nil, tall: URL(string: "https://v/t.m3u8"))

        XCTAssertEqual(squareOnly.video(tall: true)?.lastPathComponent, "s.m3u8")
        XCTAssertEqual(tallOnly.video(tall: false)?.lastPathComponent, "t.m3u8")
    }
}
