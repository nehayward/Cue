import XCTest
@testable import SonosKit

/// `GetPositionInfo` parsing for the shapes a radio source produces. The
/// player's scrubber builds a `ClosedRange` from `duration` and hands
/// `playbackPosition` in as the value, so what the parser returns for a
/// stream — no duration, a position that keeps counting — is what keeps
/// that range valid.
final class PositionInfoParserTests: XCTestCase {

    private func positionInfo(trackDuration: String, relTime: String) -> String {
        """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body>
                <u:GetPositionInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
                    <Track>1</Track>
                    <TrackDuration>\(trackDuration)</TrackDuration>
                    <TrackMetaData>
                        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
                            <item id="-1" parentID="-1" restricted="true">
                                <res protocolInfo="sonos.com-http:*:audio/mp4:*">x-sonosprog-http:song%3a1590036028.mp4?sid=204&amp;flags=8232&amp;sn=4</res>
                                <r:streamContent></r:streamContent>
                                <dc:title>Cry Your Heart Out</dc:title>
                                <upnp:class>object.item.audioItem.musicTrack</upnp:class>
                                <dc:creator>Adele</dc:creator>
                                <upnp:album>30</upnp:album>
                            </item>
                        </DIDL-Lite>
                    </TrackMetaData>
                    <TrackURI>x-sonosprog-http:song%3a1590036028.mp4?sid=204&amp;flags=8232&amp;sn=4</TrackURI>
                    <RelTime>\(relTime)</RelTime>
                    <AbsTime>NOT_IMPLEMENTED</AbsTime>
                    <RelCount>2147483647</RelCount>
                    <AbsCount>2147483647</AbsCount>
                </u:GetPositionInfoResponse>
            </s:Body>
        </s:Envelope>
        """
    }

    private func parse(trackDuration: String, relTime: String) -> Track? {
        XMLParserSonos().parsePositionInfo(
            xml: positionInfo(trackDuration: trackDuration, relTime: relTime),
            IP: "192.168.1.10",
            preferredIPForTrackAlbumArt: nil
        )
    }

    func testDurationAndPositionParseAsMilliseconds() throws {
        let track = try XCTUnwrap(parse(trackDuration: "0:04:15", relTime: "0:01:23"))
        XCTAssertEqual(track.musicService, .apple)
        XCTAssertEqual(track.duration, 255_000)
        XCTAssertEqual(track.playbackPosition, 83_000)
    }

    /// A programmed station (Apple Music radio) reports a track with no
    /// duration while its position counts up: the duration lands as zero,
    /// and the position is kept as reported.
    func testStreamWithoutDurationKeepsItsPosition() throws {
        let track = try XCTUnwrap(parse(trackDuration: "NOT_IMPLEMENTED", relTime: "0:01:23"))
        XCTAssertEqual(track.duration, 0)
        XCTAssertEqual(track.playbackPosition, 83_000)
    }

    /// A negative placeholder must not come out as a negative duration — the
    /// scrubber's `0...duration` would be an inverted range.
    func testNegativeTimesClampToZero() throws {
        let track = try XCTUnwrap(parse(trackDuration: "-1:-1:-1", relTime: "-1:-1:-1"))
        XCTAssertEqual(track.duration, 0)
        XCTAssertEqual(track.playbackPosition, 0)
    }
}
