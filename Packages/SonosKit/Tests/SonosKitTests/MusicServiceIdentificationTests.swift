import XCTest
@testable import SonosKit

final class MusicServiceIdentificationTests: XCTestCase {

    private let parser = MusicServiceParser()

    /// A playing Pandora track, as Sonos reports it in GetPositionInfo. The id
    /// carries a `::<sequence>::` field that increments per track, so the 4th
    /// track of a station reads `::3::` — which used to satisfy Plex's `:3:`
    /// heuristic and flip the whole player (heart colour, lookups, menus) to
    /// Plex partway through a station. `sid=` is authoritative and now wins.
    private func pandoraStreamURI(sequence: Int) -> String {
        "x-sonos-http:VC1%3a%3aST%3a%3aST%3a180745420102706276%3a%3aTR%3a66721664%3a%3a\(sequence)%3a%3aRINCON_74CA606E21BE01400%3a3101494893.mp3?sid=236&flags=32768&sn=22"
    }

    func testPandoraStreamIdentifiedRegardlessOfSequence() {
        for sequence in 0...5 {
            let (service, _) = parser.parse(xml: "", trackURI: pandoraStreamURI(sequence: sequence))
            XCTAssertEqual(service, .pandora, "sequence \(sequence) misidentified")
        }
    }

    /// The specific regression: sequence 3 is the one that produced `::3::`.
    func testPandoraFourthTrackIsNotPlex() {
        let (service, _) = parser.parse(xml: "", trackURI: pandoraStreamURI(sequence: 3))
        XCTAssertEqual(service, .pandora)
        XCTAssertNotEqual(service, .plex)
    }

    /// The station URI form (what browse/search rows play) still resolves.
    func testPandoraStationURI() {
        let (service, id) = parser.parse(xml: "", trackURI: "x-sonosapi-radio:ST%3A180745420102706276?sid=236&flags=32")
        XCTAssertEqual(service, .pandora)
        XCTAssertEqual(id, "ST:180745420102706276")
    }

    /// Plex's own `:3:` heuristic must keep working — it has no `sid=236`.
    func testPlexStillIdentifiedByPositionalHeuristic() {
        let (service, _) = parser.parse(xml: "", trackURI: "x-sonos-http:library%3Ametadata%3A3%3A12345.flac?sid=212&flags=8224")
        XCTAssertEqual(service, .plex)
    }

    /// A Plex song whose id has another number where Clic's own ids carry 3
    /// is still Plex by its sid, and keeps the whole id for the rating lookup.
    func testPlexIdentifiedBySidWithoutThreeHeuristic() {
        let (service, id) = parser.parse(xml: "", trackURI: "x-sonosapi-hls-static:10036020b9c7c12bf5f64e85a1a12a53f4e74f69%3A5%3A67890%3Atrack?sid=212&flags=8232&sn=9")
        XCTAssertEqual(service, .plex)
        XCTAssertEqual(id, "10036020b9c7c12bf5f64e85a1a12a53f4e74f69:5:67890")
    }

    /// The Plex account in the DIDL metadata identifies it without a sid.
    func testPlexIdentifiedByServiceAccount() {
        let (service, _) = parser.parse(xml: "SA_RINCON54279_X_#Svc54279-0-Token", trackURI: "x-sonosapi-hls-static:10036020b9c7c12bf5f64e85a1a12a53f4e74f69%3A5%3A67890%3Atrack")
        XCTAssertEqual(service, .plex)
    }

    /// `sid=212` must not claim a longer service id that starts with 212.
    func testPlexSidDoesNotMatchLongerIDs() {
        let (service, _) = parser.parse(xml: "", trackURI: "x-sonos-http:track%3A12345.mp3?sid=2120&flags=8224")
        XCTAssertNotEqual(service, .plex)
    }

    /// Sonos Radio shares the `x-sonosapi-radio:` shape and sits next to
    /// Pandora in the same ordering, so pin it too.
    func testSonosRadioStationURI() {
        let (service, _) = parser.parse(xml: "", trackURI: "x-sonosapi-radio:sonos%3A2997?sid=303&flags=32")
        XCTAssertEqual(service, .sonosRadio)
    }

    /// A queued Subsonic track is a plain HTTP hit on the server's
    /// `/rest/stream` endpoint; the song id is the `id` query parameter.
    func testSubsonicStreamURI() {
        let uri = "http://192.168.1.20:4533/rest/stream?id=abc123&u=admin&t=26719a1196d2a940705a59634eb18eab&s=c19b2d&v=1.16.1&c=Cue&f=json"
        let (service, id) = parser.parse(xml: "", trackURI: uri)
        XCTAssertEqual(service, .subsonic)
        XCTAssertEqual(id, "abc123")

        let lookup = parser.lookup(uri: uri, serviceID: "", type: .track)
        XCTAssertEqual(lookup?.0, .subsonic)
        XCTAssertEqual(lookup?.1, "abc123")
        XCTAssertEqual(lookup?.2, .track)
    }

    /// A Subsonic server on a port containing "3" must not trip the Plex
    /// `:3:` heuristic, and an https reverse-proxy address still resolves.
    func testSubsonicBeatsPlexHeuristic() {
        let (service, id) = parser.parse(xml: "", trackURI: "https://music.example.com/subsonic/rest/stream?id=tr-9&u=me&t=t&s=s&v=1.16.1&c=Cue")
        XCTAssertEqual(service, .subsonic)
        XCTAssertEqual(id, "tr-9")
    }
}
