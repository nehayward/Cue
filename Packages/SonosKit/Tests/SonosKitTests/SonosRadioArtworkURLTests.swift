import XCTest
@testable import SonosKit

final class SonosRadioArtworkURLTests: XCTestCase {

    /// The sali proxy serves the w=60 row thumbnail. Unwrapping to the inner
    /// imgix URL at a real size fixes the blurry player artwork and sidesteps
    /// the proxy's flaky 503s.
    func testUnwrapsSaliProxyToInnerImgixURLAtRequestedWidth() throws {
        let proxy = try XCTUnwrap(URL(string:
            "https://sali.sonos.superhi.fi/image?w=60&image=https%3A%2F%2Fsonosradio.imgix.net%2Fstation-images%2Fabc.png%3Fw%3D200%26auto%3Dformat%2Ccompress%26partnerId%3Dsonos"
        ))
        let upscaled = proxy.sonosRadioArtwork(width: 800)
        let components = try XCTUnwrap(URLComponents(url: upscaled, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "sonosradio.imgix.net")
        XCTAssertEqual(components.path, "/station-images/abc.png")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "w" })?.value, "800")
        // The other imgix params survive.
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "partnerId" })?.value, "sonos")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "auto" })?.value, "format,compress")
    }

    func testBumpsWidthOnDirectImgixURL() throws {
        let direct = try XCTUnwrap(URL(string: "https://sonosradio.imgix.net/station-images/abc.jpeg?w=60&auto=format"))
        let upscaled = direct.sonosRadioArtwork(width: 800)
        XCTAssertTrue(upscaled.absoluteString.contains("w=800"))
        XCTAssertFalse(upscaled.absoluteString.contains("w=60"))
    }

    func testAddsWidthWhenImgixURLHasNone() throws {
        let direct = try XCTUnwrap(URL(string: "https://sonosradio.imgix.net/station-images/abc.jpeg"))
        XCTAssertTrue(direct.sonosRadioArtwork(width: 800).absoluteString.contains("w=800"))
    }

    /// Applied at the parser level where all radio art flows through, so
    /// everything that isn't Sonos Radio must pass through untouched.
    func testLeavesOtherHostsUntouched() throws {
        let tuneIn = try XCTUnwrap(URL(string: "https://cdn-profiles.tunein.com/s24939/images/logoq.jpg?w=60"))
        XCTAssertEqual(tuneIn.sonosRadioArtwork(), tuneIn)
        let speaker = try XCTUnwrap(URL(string: "http://192.168.1.10:1400/getaa?s=1&u=x"))
        XCTAssertEqual(speaker.sonosRadioArtwork(), speaker)
    }

    /// A malformed proxy URL (missing or non-http inner image param) falls
    /// back to itself rather than returning nil or garbage.
    func testMalformedProxyFallsBackToSelf() throws {
        let noImage = try XCTUnwrap(URL(string: "https://sali.sonos.superhi.fi/image?w=60"))
        XCTAssertEqual(noImage.sonosRadioArtwork(), noImage)
    }
}
