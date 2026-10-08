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

    // MARK: Line-in

    /// The stream names the speaker whose input it is, which can be any
    /// speaker in the household, not the group's own.
    func testLineInTrackNamesItsSourceSpeaker() throws {
        let xml = """
        <s:Envelope><s:Body><u:GetPositionInfoResponse>\
        <Track>1</Track><TrackDuration>0:00:00</TrackDuration>\
        <TrackMetaData>NOT_IMPLEMENTED</TrackMetaData>\
        <TrackURI>x-rincon-stream:RINCON_000E58AABBCC01400</TrackURI>\
        <RelTime>0:01:12</RelTime>\
        </u:GetPositionInfoResponse></s:Body></s:Envelope>
        """
        let track = try XCTUnwrap(SonosTrackParser.parse(xmlString: xml, ip: "192.168.1.20", preferredIP: nil))
        XCTAssertEqual(track.name, "Line In")
        XCTAssertEqual(track.lineInSourceID, "RINCON_000E58AABBCC01400")
        XCTAssertFalse(track.isEmpty)
    }

    /// A Move 2 playing its own input reports it with the input's number.
    func testLineInSourceDropsTheInputNumber() {
        XCTAssertEqual(Track.lineIn(uri: "x-rincon-stream:RINCON_C43875011B7C01400:0").lineInSourceID, "RINCON_C43875011B7C01400")
    }

    func testOnlyLineInTracksHaveASource() {
        XCTAssertNil(Track.tv.lineInSourceID)
        XCTAssertNil(Track(trackID: "song:123").lineInSourceID)
        XCTAssertNil(Track(trackID: "x-rincon-stream:").lineInSourceID)
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
