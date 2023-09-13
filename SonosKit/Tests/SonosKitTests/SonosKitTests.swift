import XCTest
@testable import SonosKit

final class SonosKitTests: XCTestCase {
    func testXMLParse() throws {
        let zone = Bundle.module.url(forResource: "Zone", withExtension: "xml")
        let zoneXML = try! String(contentsOf: zone!)
        XMLParserSonos().parse(xml: zoneXML)
    }

    func testVolumeResponseParse() throws {
        let getVolumeResponseXMLURL = Bundle.module.url(forResource: "GetVolumeResponse", withExtension: "xml")
        let volumeXML = try! String(contentsOf: getVolumeResponseXMLURL!)
        XMLParserSonos().parseVolume(xml: volumeXML)
    }

    func testZoneEventXMLParse() throws {
        let zone = Bundle.module.url(forResource: "ZoneEvent", withExtension: "xml")
        let zoneXML = try! String(contentsOf: zone!)
        let zones = XMLParserSonos().parseZonesEvent(xml: zoneXML.unescaped)
        print(zones)
        XCTAssertEqual(zones.count, 4)
    }

    func testZoneXMLParse() throws {
        let zone = Bundle.module.url(forResource: "Zone", withExtension: "xml")
        let zoneXML = try! String(contentsOf: zone!)
        let zones = XMLParserSonos().parseZones(xml: zoneXML)
        print(zones)
        XCTAssertEqual(zones.count, 5)
    }

    func testGetPositionParse() throws {
        let track = Bundle.module.url(forResource: "GetPositionInfoApple", withExtension: "xml")
        let trackXML = try! String(contentsOf: track!)
        print(trackXML)
        let positionInfo = XMLParserSonos().parsePositionInfo(xml: trackXML)
        XCTAssertNotNil(positionInfo)
        XCTAssert(positionInfo?.musicService == .apple)
    }

    func testGetPositionInfoSpotifyParse() throws {
        let track = Bundle.module.url(forResource: "GetPositionInfoSpotify", withExtension: "xml")
        let trackXML = try! String(contentsOf: track!)
        print(trackXML)
        let positionInfo = XMLParserSonos().parsePositionInfo(xml: trackXML)
        XCTAssertNotNil(positionInfo)
        XCTAssert(positionInfo?.musicService == .spotify)
    }

    func testPlaybackInfoParse() throws {
        let transportInfoURL = Bundle.module.url(forResource: "GetTransportInfo", withExtension: "xml")
        let transportInfoXML = try! String(contentsOf: transportInfoURL!)
        let playbackState = XMLParserSonos().parsePlaybackInfo(xml: transportInfoXML)
        print(playbackState)
    }

    func testGetZoneGroupAttributes() throws {
        let getZoneGroupAttributesURL = Bundle.module.url(forResource: "GetZoneGroupAttributes", withExtension: "xml")
        let getZoneGroupAttributesXML = try! String(contentsOf: getZoneGroupAttributesURL!)
        print(getZoneGroupAttributesXML)

        let householdID = XMLParserSonos().parseHouseID(xml: getZoneGroupAttributesXML)
        print(householdID)
    }

    func testGetQueueParsing() throws {
        let getQueueURL = Bundle.module.url(forResource: "GetQueue", withExtension: "xml")
        let getQueueXML = try! String(contentsOf: getQueueURL!)
        let tracks = XMLParserSonos().parseQueue(xml: getQueueXML)
        XCTAssertEqual(tracks.count, 25)
    }

    func testGetCurrentTransportActions() throws {
        let xmlURL = Bundle.module.url(forResource: "GetCurrentTransportActions", withExtension: "xml")
        let xml = try String(contentsOf: xmlURL!)
        let availableActions = try XCTUnwrap(XMLParserSonos().parseGetCurrentTransportActions(xml: xml))
        XCTAssert(availableActions.contains([.next,.pause]))
    }
}
