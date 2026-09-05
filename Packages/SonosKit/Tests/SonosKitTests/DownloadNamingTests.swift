import XCTest
@testable import SonosKit

final class DownloadNamingTests: XCTestCase {

    private func item(_ service: MusicService, id: String, codec: String? = nil) -> PlayableContent {
        PlayableContent(
            title: "T", subtitle: "S", thumbnail: nil, artwork: nil,
            content: .init(service: service, id: id, type: .track, location: nil),
            previewURL: URL(string: "https://server.local/rest/stream?id=\(id)"),
            metadata: .init(audioCodec: codec)
        )
    }

    func testPlexKeepsTheBareIDSoOldDownloadsCarryOver() {
        XCTAssertEqual(DownloadNaming.key(for: item(.plex, id: "12345")), "12345")
    }

    func testOtherServicesArePrefixedAndMadeFilesystemSafe() {
        XCTAssertEqual(DownloadNaming.key(for: item(.subsonic, id: "tr/ab:c.d")), "subsonic-tr-ab-c-d")
        XCTAssertEqual(DownloadNaming.key(for: item(.plex, id: "library/metadata/9.1")), "library-metadata-9-1")
    }

    func testKeysAreDistinctAcrossServicesForTheSameID() {
        XCTAssertNotEqual(DownloadNaming.key(for: item(.plex, id: "1")), DownloadNaming.key(for: item(.subsonic, id: "1")))
    }

    func testFileExtensionPrefersAShortCodecThenTheURLThenMP3() {
        let url = URL(string: "https://s/rest/stream?id=1&ext=.flac")!
        XCTAssertEqual(DownloadNaming.fileExtension(for: item(.subsonic, id: "1", codec: " FLAC "), url: url), "flac")
        XCTAssertEqual(DownloadNaming.fileExtension(for: item(.subsonic, id: "1", codec: "audio/mpeg"), url: URL(string: "https://s/a/b.M4A")!), "m4a",
                       "A MIME type is not an extension; fall back to the URL")
        XCTAssertEqual(DownloadNaming.fileExtension(for: item(.subsonic, id: "1"), url: URL(string: "https://s/stream?id=1")!), "mp3")
    }

    func testTaskDescriptionRoundTrips() {
        let description = DownloadNaming.taskDescription(key: "subsonic-1", fileExtension: "flac")
        XCTAssertEqual(description, "subsonic-1|flac")
        let parsed = DownloadNaming.parseTaskDescription(description)
        XCTAssertEqual(parsed?.key, "subsonic-1")
        XCTAssertEqual(parsed?.fileExtension, "flac")
    }

    func testTaskDescriptionRejectsMalformedValues() {
        XCTAssertNil(DownloadNaming.parseTaskDescription(nil))
        XCTAssertNil(DownloadNaming.parseTaskDescription(""))
        XCTAssertNil(DownloadNaming.parseTaskDescription("no-separator"))
        XCTAssertNil(DownloadNaming.parseTaskDescription("|flac"))
        XCTAssertNil(DownloadNaming.parseTaskDescription("key|"))
    }

    func testProgressIsClampedAndZeroUntilSizeKnown() {
        XCTAssertEqual(DownloadNaming.progress(received: 50, expected: 200), 0.25)
        XCTAssertEqual(DownloadNaming.progress(received: 300, expected: 200), 1)
        XCTAssertEqual(DownloadNaming.progress(received: 10, expected: 0), 0)
        XCTAssertEqual(DownloadNaming.progress(received: 10, expected: -1), 0, "NSURLSessionTransferSizeUnknown is -1")
    }
}
