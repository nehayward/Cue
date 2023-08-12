import XCTest
@testable import SonosKit

final class SonosKitTests: XCTestCase {
    func testXMLParse() throws {
        let zone = Bundle.module.url(forResource: "Zone", withExtension: "xml")
        let zoneXML = try! String(contentsOf: zone!)
//        print(zoneXML)
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


//    func testTackParse() throws {
//        let track = Bundle.module.url(forResource: "Track", withExtension: "xml")
//        let trackXML = try! String(contentsOf: track!)
////        print(zoneXML)
//        let songTrack = XMLParserSonos().parseTrackInfo(xml: trackXML)
//        print(songTrack)
//    }

    func testGetPositionParse() throws {
        let track = Bundle.module.url(forResource: "GetPosition", withExtension: "xml")
        let trackXML = try! String(contentsOf: track!)
        print(trackXML)
        let positionInfo = XMLParserSonos().parsePositionInfo(xml: trackXML)
        XCTAssertNotNil(positionInfo)
    }


    func testRendererControlParse() throws {
        let track = Bundle.module.url(forResource: "RendererControl", withExtension: "xml")
        let trackXML = try! String(contentsOf: track!)
        let positionInfo = XMLParserSonos().parseRendererControl(xml: trackXML)
        print(positionInfo)
    }

    func testPlaybackInfoParse() throws {
        let transportInfoURL = Bundle.module.url(forResource: "GetTransportInfo", withExtension: "xml")
        let transportInfoXML = try! String(contentsOf: transportInfoURL!)
//        print(zoneXML)
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
}
