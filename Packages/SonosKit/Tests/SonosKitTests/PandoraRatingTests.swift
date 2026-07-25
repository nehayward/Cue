import XCTest
@testable import SonosKit

final class PandoraRatingTests: XCTestCase {

    /// Sonos reports a playing Pandora track as an `x-sonos-http:` stream whose
    /// id carries the station, the track, and the player, ending in a file
    /// extension. `MusicServiceParser` keeps everything between the scheme and
    /// the query, so the SMAPI id `rateItem` wants is that value minus the
    /// extension. Taken from a capture of the official controller.
    func testStripsStreamFileExtension() {
        let parsed = "VC1::ST::ST:180745420102706276::TR:66721664::0::RINCON_74CA606E21BE01400:3101494893.mp3"
        XCTAssertEqual(
            MusicSearchService.pandoraSMAPITrackID(from: parsed),
            "VC1::ST::ST:180745420102706276::TR:66721664::0::RINCON_74CA606E21BE01400:3101494893"
        )
    }

    /// Only a trailing extension is dropped — the dots and colons inside the
    /// id (the RINCON serial, the `::` separators) are part of it.
    func testKeepsInteriorPunctuation() {
        let id = "VC1::ST::ST:1::TR:2::0::RINCON_ABC:3101494893"
        XCTAssertEqual(MusicSearchService.pandoraSMAPITrackID(from: id), id)
    }

    /// A station id from browse/search has no extension and must pass through
    /// untouched, so a mis-wired caller fails loudly rather than silently
    /// rating a truncated id.
    func testLeavesStationIDsAlone() {
        XCTAssertEqual(MusicSearchService.pandoraSMAPITrackID(from: "ST:180745420102706276"), "ST:180745420102706276")
        XCTAssertEqual(MusicSearchService.pandoraSMAPITrackID(from: "SF:16722:220553"), "SF:16722:220553")
    }

    func testHandlesOtherAudioExtensions() {
        XCTAssertEqual(MusicSearchService.pandoraSMAPITrackID(from: "VC1::TR:9.m4a"), "VC1::TR:9")
        XCTAssertEqual(MusicSearchService.pandoraSMAPITrackID(from: "VC1::TR:9.flac"), "VC1::TR:9")
    }

    func testEmptyIDIsUnchanged() {
        XCTAssertEqual(MusicSearchService.pandoraSMAPITrackID(from: ""), "")
    }
}
