import XCTest
@testable import SonosKit

final class StringParsingTests: XCTestCase {

    /// The Sonos Radio artwork proxy URL keeps its `&` query separators when
    /// embedded in DIDL metadata: `&` must become `&amp;amp;` (double-escaped,
    /// like the `<res>` URIs), NOT `%26` — percent-encoding the separators
    /// corrupts the URL and the artwork host 503s when the speaker
    /// round-trips it back as albumArtURI.
    func testDidlEscapedDoubleEscapesAmpersands() {
        let url = "https://sali.sonos.superhi.fi/image?w=60&image=https%3A%2F%2Fsonosradio.imgix.net%2Fstation.png%3Fw%3D200%26auto%3Dformat&partnerId=sonos"
        let escaped = url.didlEscaped
        XCTAssertEqual(
            escaped,
            "https://sali.sonos.superhi.fi/image?w=60&amp;amp;image=https%3A%2F%2Fsonosradio.imgix.net%2Fstation.png%3Fw%3D200%26auto%3Dformat&amp;amp;partnerId=sonos"
        )
        // Percent-encoded ampersands inside the nested URL are data, not
        // separators — they must survive untouched.
        XCTAssertTrue(escaped.contains("%26auto%3Dformat"))
    }

    /// Round trip: what the speaker sends back decodes to the original URL.
    /// GetMediaInfo parsing runs `removingHTMLEntities()` twice (once for the
    /// metadata blob, once for the extracted albumArtURI).
    func testDidlEscapedRoundTripsThroughEntityDecoding() {
        let url = "https://sali.sonos.superhi.fi/image?w=60&image=x&partnerId=sonos"
        let decoded = url.didlEscaped.removingHTMLEntities().removingHTMLEntities()
        XCTAssertEqual(decoded, url)
    }

    func testDidlEscapedNormalizesSingleEscapedInput() {
        XCTAssertEqual("a&amp;b".didlEscaped, "a&amp;amp;b")
        XCTAssertEqual("no-ampersands".didlEscaped, "no-ampersands")
    }
}
