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

    /// Sonos Radio shares the `x-sonosapi-radio:` shape and sits next to
    /// Pandora in the same ordering, so pin it too.
    func testSonosRadioStationURI() {
        let (service, _) = parser.parse(xml: "", trackURI: "x-sonosapi-radio:sonos%3A2997?sid=303&flags=32")
        XCTAssertEqual(service, .sonosRadio)
    }
}
