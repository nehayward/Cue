import XCTest
@testable import SonosKit

/// A speaker's `CurrentURI` → the stream this device opens to recognize the
/// song on it. Only the cases that need no network — a TuneIn id goes to
/// TuneIn for its stream.
final class RadioStreamURLTests: XCTestCase {

    func testMP3RadioBareHostBecomesHTTP() async {
        let url = await SonosService.radioStreamURL(forTransportURI: "x-rincon-mp3radio://stream.example.com:8000/live.mp3")
        XCTAssertEqual(url, URL(string: "http://stream.example.com:8000/live.mp3"))
    }

    func testMP3RadioWithSchemeKeepsIt() async {
        let url = await SonosService.radioStreamURL(forTransportURI: "x-rincon-mp3radio://https://stream.example.com/live")
        XCTAssertEqual(url, URL(string: "https://stream.example.com/live"))
    }

    func testPlainHTTPIsItself() async {
        let url = await SonosService.radioStreamURL(forTransportURI: "https://stream.example.com/live.aac")
        XCTAssertEqual(url, URL(string: "https://stream.example.com/live.aac"))
    }

    func testSpeakerOnlySourcesHaveNoStream() async {
        let sonosRadio = await SonosService.radioStreamURL(forTransportURI: "x-sonosapi-radio:sonos%3A2997?sid=303&flags=32")
        XCTAssertNil(sonosRadio)
        let nonTuneIn = await SonosService.radioStreamURL(forTransportURI: "x-sonosapi-stream:p12345?sid=254")
        XCTAssertNil(nonTuneIn)
        let lineIn = await SonosService.radioStreamURL(forTransportURI: "x-rincon-stream:RINCON_000E58123456")
        XCTAssertNil(lineIn)
    }
}
