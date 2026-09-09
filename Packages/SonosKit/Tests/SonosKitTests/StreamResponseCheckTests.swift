@testable import SonosKit
import XCTest

final class StreamResponseCheckTests: XCTestCase {
    private let url = URL(string: "http://plex.local:32400/music/:/transcode/universal/start.ogg")!

    private func response(status: Int, mime: String?) -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let mime { headers["Content-Type"] = mime }
        return HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    func testAudioResponsePasses() {
        XCTAssertNil(StreamResponseCheck.refusal(in: response(status: 200, mime: "audio/ogg")))
        XCTAssertNil(StreamResponseCheck.refusal(in: response(status: 200, mime: nil)))
        XCTAssertNil(StreamResponseCheck.refusal(in: nil))
    }

    /// Plex's answer to a transcode it has no target for: an 89-byte
    /// "400 Bad Request" page that a download task hands over as finished.
    func testRefusedPageIsAnError() throws {
        let refused = try XCTUnwrap(StreamResponseCheck.refusal(in: response(status: 400, mime: "text/html")))
        XCTAssertEqual(refused.statusCode, 400)
        XCTAssertTrue(refused.errorDescription?.contains("HTTP 400") == true)
        XCTAssertNotNil(StreamResponseCheck.refusal(in: response(status: 200, mime: "text/xml")))
        XCTAssertNotNil(StreamResponseCheck.refusal(in: response(status: 200, mime: "application/json")))
        XCTAssertNotNil(StreamResponseCheck.refusal(in: response(status: 500, mime: "audio/mpeg")))
    }
}
