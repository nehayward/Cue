import XCTest
@testable import SonosKit

final class TrackTests: XCTestCase {

    // MARK: isEmpty vs == .empty

    func testEmptyTrackIsEmpty() {
        XCTAssertTrue(Track.empty.isEmpty)
        XCTAssertEqual(Track.empty, .empty)
    }

    /// A radio source stamps station artwork onto an otherwise-empty track
    /// (idle station / ad break). That track must still read as empty —
    /// comparing with `== .empty` instead made SonosService alternate between
    /// "fill in station art" and "reset to .empty" every pulse, flickering
    /// the player. See the empty-track handling in SonosService.load().
    func testEmptyTrackWithStationArtworkIsStillEmpty() {
        var track = Track.empty
        track.radioStationArtworkURL = URL(string: "https://sonosradio.example/station.png")
        XCTAssertTrue(track.isEmpty)
        XCTAssertNotEqual(track, .empty, "full equality still distinguishes the branded resting track")
    }

    func testTracksWithIDOrNameAreNotEmpty() {
        XCTAssertFalse(Track(trackID: "song:123").isEmpty)
        XCTAssertFalse(Track(trackID: "", name: "Loading…").isEmpty)
        XCTAssertFalse(Track.tv.isEmpty)
        XCTAssertFalse(Track.alarm.isEmpty)
    }

    // MARK: artworkURL fallback order

    func testArtworkURLPrefersDownloadedThenSonosThenStation() {
        let downloaded = URL(string: "https://cdn.example/track.jpg")!
        let sonos = URL(string: "http://192.168.1.10:1400/getaa?u=x")!
        let station = URL(string: "https://sonosradio.example/station.png")!

        var track = Track(trackID: "1", name: "Song")
        track.radioStationArtworkURL = station
        XCTAssertEqual(track.artworkURL, station)

        track.sonosAlbumArtURL = sonos
        XCTAssertEqual(track.artworkURL, sonos)

        track.downloadedArtworkURL = downloaded
        XCTAssertEqual(track.artworkURL, downloaded)
    }

    /// The branded resting track keeps showing the station logo even though
    /// the track itself is empty.
    func testEmptyRadioTrackStillExposesStationArtwork() {
        let station = URL(string: "https://sonosradio.example/station.png")!
        var track = Track.empty
        track.radioStationArtworkURL = station
        XCTAssertEqual(track.artworkURL, station)
    }
}
