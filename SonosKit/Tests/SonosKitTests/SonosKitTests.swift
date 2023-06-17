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

    func testZoneXMLParse() throws {
        let zone = Bundle.module.url(forResource: "Zone", withExtension: "xml")
        let zoneXML = try! String(contentsOf: zone!)
//        print(zoneXML)
        let zones = XMLParserSonos().parseZones(xml: zoneXML)
        XCTAssertEqual(zones.count, 5)
    }


    func testTackParse() throws {
        let track = Bundle.module.url(forResource: "Track", withExtension: "xml")
        let trackXML = try! String(contentsOf: track!)
//        print(zoneXML)
        let songTrack = XMLParserSonos().parseTrackInfo(xml: trackXML)
        print(songTrack)
    }

    func testGetPositionParse() throws {
        let track = Bundle.module.url(forResource: "GetPosition", withExtension: "xml")
        let trackXML = try! String(contentsOf: track!)
//        print(zoneXML)
        let positionInfo = XMLParserSonos().parsePositionInfo(xml: trackXML)
        print(positionInfo)
    }


    func testRendererControlParse() throws {
        let track = Bundle.module.url(forResource: "RendererControl", withExtension: "xml")
        let trackXML = try! String(contentsOf: track!)
        let positionInfo = XMLParserSonos().parseRendererControl(xml: trackXML)
        print(positionInfo)
    }
}
