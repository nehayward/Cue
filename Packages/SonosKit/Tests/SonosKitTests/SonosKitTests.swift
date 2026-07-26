import XCTest
@testable import SonosKit

final class SonosKitTests: XCTestCase {
    let sonosService = SonosService()
    let sonosAPI = SonosAPI()

    func testXMLParse() throws {
        let zone = Bundle.module.url(forResource: "Zone", withExtension: "xml")
        let zoneXML = try! String(contentsOf: zone!)
        let zones = XMLParserSonos().parseZones(xml: zoneXML)
        XCTAssertEqual(zones.count, 5)
    }
    
    func testXMLMarkParse() throws {
        let zone = Bundle.module.url(forResource: "ZoneMark", withExtension: "xml")
        let zoneXML = try! String(contentsOf: zone!)
        let zones = XMLParserSonos().parseZones(xml: zoneXML)
        XCTAssertEqual(zones.count, 7)
    }
    
    func testXMLEscapedParse() throws {
        let zone = Bundle.module.url(forResource: "ZoneEscaped", withExtension: "xml")
        let zoneXML = try! String(contentsOf: zone!)
        let zones = XMLParserSonos().parseZones(xml: zoneXML)
        XCTAssertEqual(zones.count, 7)
    }
    
    func testXMLMattZoneParse() throws {
        let zone = Bundle.module.url(forResource: "ZoneMatt", withExtension: "xml")
        let zoneXML = try! String(contentsOf: zone!)
        let zones = XMLParserSonos().parseZones(xml: zoneXML)
        XCTAssertEqual(zones.count, 8)
    }
    
    func testHouseholdControlIDParseFromStatusZP() throws {
        // S1 players (ZP100 etc.) don't report CurrentMuseHouseholdId; their
        // household comes from /status/zp's HouseholdControlID instead.
        let statusZP = """
        <?xml version="1.0" ?>
        <ZPSupportInfo><ZPInfo><ZoneName>Living Room</ZoneName>\
        <LocalUID>RINCON_000E58AAAAAA01400</LocalUID>\
        <HouseholdControlID>Sonos_vKO8NuKV8cwCRWMPY4z5xErrhA</HouseholdControlID>\
        </ZPInfo></ZPSupportInfo>
        """
        let id = try XMLParserSonos().parseValue(xml: statusZP, named: "HouseholdControlID")
        XCTAssertEqual(id, "Sonos_vKO8NuKV8cwCRWMPY4z5xErrhA")
    }

    func testParseHouseIDEmptyOnS1Attributes() throws {
        // An S1 GetZoneGroupAttributes response has no CurrentMuseHouseholdId —
        // parseHouseID must return empty (triggering the /status/zp fallback)
        // rather than some other field's value.
        let s1Attributes = """
        <s:Envelope><s:Body><u:GetZoneGroupAttributesResponse>\
        <CurrentZoneGroupName>Living Room</CurrentZoneGroupName>\
        <CurrentZoneGroupID>RINCON_000E58AAAAAA01400:12</CurrentZoneGroupID>\
        <CurrentZonePlayerUUIDsInGroup>RINCON_000E58AAAAAA01400</CurrentZonePlayerUUIDsInGroup>\
        </u:GetZoneGroupAttributesResponse></s:Body></s:Envelope>
        """
        XCTAssertEqual(XMLParserSonos().parseHouseID(xml: s1Attributes), "")
    }

    func testXMLParserDelegatePerformance() {
        measure {
            let zone = Bundle.module.url(forResource: "ZoneMatt", withExtension: "xml")
            let zoneXML = try! String(contentsOf: zone!)
            let parser = XMLParserSonos().parseZones(xml: zoneXML)
        }
    }
    
//    func testRegexParserPerformance() {
//        measure {
//            let zone = Bundle.module.url(forResource: "ZoneMatt", withExtension: "xml")
//            let zoneXML = try! String(contentsOf: zone!)
//            let parser = ZoneGroupRegexParser()
//            parser.parse(data: zoneXML)
//        }
//    }

    func testVolumeResponseParse() throws {
        let getVolumeResponseXMLURL = Bundle.module.url(forResource: "GetVolumeResponse", withExtension: "xml")
        let volumeXML = try String(contentsOf: getVolumeResponseXMLURL!)
        let volume = try XMLParserSonos().parseVolume(xml: volumeXML)
        XCTAssert(volume == 80)
    }

//    func testZoneEventXMLParse() throws {
//        let zone = Bundle.module.url(forResource: "ZoneEvent", withExtension: "xml")
//        let zoneXML = try! String(contentsOf: zone!)
//        let zones = XMLParserSonos().parseZonesEvent(xml: zoneXML.unescaped)
//        print(zones)
//        XCTAssertEqual(zones.count, 4)
//    }

    func testZoneXMLParse() throws {
        let zone = Bundle.module.url(forResource: "Zone", withExtension: "xml")
        let zoneXML = try! String(contentsOf: zone!)
        let zones = XMLParserSonos().parseZones(xml: zoneXML)
        print(zones)
        XCTAssertEqual(zones.count, 5)
    }

    func testZoneWithVanishedXMLParse() throws {
        let zone = Bundle.module.url(forResource: "ZonesVanished", withExtension: "xml")
        let vanishedDevicesXML = try! String(contentsOf: zone!)
        let vanishedDevices = XMLParserSonos().parseVanishedDevices(xml: vanishedDevicesXML)
        print(vanishedDevices)
        XCTAssertEqual(vanishedDevices.count, 2)
    }

    func testZoneBoostXMLParse() throws {
        let zone = Bundle.module.url(forResource: "ZoneWithBoost", withExtension: "xml")
        let zoneXML = try! String(contentsOf: zone!)
        let zones = XMLParserSonos().parseZones(xml: zoneXML)
        print(zones)
        XCTAssertEqual(zones.count, 2)
    }

//    func testGetPositionParse() throws {
//        let track = Bundle.module.url(forResource: "GetPositionInfoApple", withExtension: "xml")
//        let trackXML = try! String(contentsOf: track!)
//        print(trackXML)
//        let positionInfo = XMLParserSonos().parsePositionInfo(xml: trackXML, IP: "")
//        XCTAssertNotNil(positionInfo)
//        XCTAssert(positionInfo?.musicService == .apple)
//    }
//
//    func testGetPositionInfoSpotifyParse() throws {
//        let track = Bundle.module.url(forResource: "GetPositionInfoSpotify", withExtension: "xml")
//        let trackXML = try! String(contentsOf: track!)
//        print(trackXML)
//        let positionInfo = XMLParserSonos().parsePositionInfo(xml: trackXML, IP: "")
//        XCTAssertNotNil(positionInfo)
//        XCTAssert(positionInfo?.musicService == .spotify)
//    }
//
//    func testGetPositionInfoSpotifyStreamParse() throws {
//        let track = Bundle.module.url(forResource: "GetPositionInfoSpotifyStream", withExtension: "xml")
//        let trackXML = try! String(contentsOf: track!)
//        print(trackXML)
//        let positionInfo = XMLParserSonos().parsePositionInfo(xml: trackXML, IP: "")
//        XCTAssertNotNil(positionInfo)
//        XCTAssert(positionInfo?.musicService == .spotify)
//    }
//
//    func testPlaybackInfoParse() throws {
//        let transportInfoURL = Bundle.module.url(forResource: "GetTransportInfo", withExtension: "xml")
//        let transportInfoXML = try! String(contentsOf: transportInfoURL!)
//        let playbackState = XMLParserSonos().parsePlaybackInfo(xml: transportInfoXML)
//        print(playbackState)
//    }
//
//    func testGetZoneGroupAttributes() throws {
//        let getZoneGroupAttributesURL = Bundle.module.url(forResource: "GetZoneGroupAttributes", withExtension: "xml")
//        let getZoneGroupAttributesXML = try! String(contentsOf: getZoneGroupAttributesURL!)
//        print(getZoneGroupAttributesXML)
//
//        let householdID = XMLParserSonos().parseHouseID(xml: getZoneGroupAttributesXML)
//        print(householdID)
//    }
//
//    func testGetQueueParsing() throws {
//        let getQueueURL = Bundle.module.url(forResource: "GetQueue", withExtension: "xml")
//        let getQueueXML = try! String(contentsOf: getQueueURL!)
//        let tracks = XMLParserSonos().parseQueue(IP: "", xml: getQueueXML)
//        XCTAssertEqual(tracks.count, 25)
//    }
//    
//    func testGetQueueLargeParsing() throws {
//        let getQueueLargeURL = Bundle.module.url(forResource: "GetQueueLarge", withExtension: "xml")
//        let getQueueLargeXML = try! String(contentsOf: getQueueLargeURL!)
//
//        measure {
//            let _ = XMLParserSonos().parseQueue(IP: "", xml: getQueueLargeXML)
//        }
//    }
//
//    func testGetQueueLargeFastParsing() throws {
//        let getQueueLargeURL = Bundle.module.url(forResource: "GetQueueLarge", withExtension: "xml")
//        let getQueueLargeXML = try! String(contentsOf: getQueueLargeURL!)
//
//        measure {
//            let _ = XMLParserSonos().parseQueue(IP: "", xml: getQueueLargeXML)
//        }
//    }
//
//    func testGetQueueSmallParsing() throws {
//        let getQueueURL = Bundle.module.url(forResource: "GetQueue", withExtension: "xml")
//        let getQueueXML = try! String(contentsOf: getQueueURL!)
//
//        measure {
//            let _ = XMLParserSonos().parseQueue(IP: "", xml: getQueueXML)
//        }
//    }

//    func testGetCurrentTransportActions() throws {
//        let xmlURL = Bundle.module.url(forResource: "GetCurrentTransportActions", withExtension: "xml")
//        let xml = try String(contentsOf: xmlURL!)
//        let availableActions = try XCTUnwrap(XMLParserSonos().parseGetCurrentTransportActions(xml: xml))
//        XCTAssert(availableActions.contains([.next,.pause]))
//    }

    func testParseSpotifyURL() {
        let spotifyPlaylistURL = URL(string: "https://open.spotify.com/playlist/6zKUeBJeJQODG5o2PzxRsZ")!
        XCTAssertEqual(sonosAPI.parse(url: spotifyPlaylistURL), MediaContent(service: .spotify, id: "6zKUeBJeJQODG5o2PzxRsZ", type: .playlist, location: spotifyPlaylistURL))

        let spotifyAlbumURL = URL(string: "https://open.spotify.com/album/7fJJK56U9fHixgO0HQkhtI")!
        XCTAssertEqual(sonosAPI.parse(url: spotifyAlbumURL), MediaContent(service: .spotify, id: "7fJJK56U9fHixgO0HQkhtI", type: .album, location: spotifyAlbumURL))

        let spotifyArtistURL = URL(string: "https://open.spotify.com/artist/6M2wZ9GZgrQXHCFfjv46we")!
        XCTAssertEqual(sonosAPI.parse(url: spotifyArtistURL), MediaContent(service: .spotify, id: "6M2wZ9GZgrQXHCFfjv46we", type: .artist, location: spotifyArtistURL))

        let spotifyTrackURL = URL(string: "https://open.spotify.com/track/5bGNsC7FTQ3WZzz0XYOmvZ")!
        XCTAssertEqual(sonosAPI.parse(url: spotifyTrackURL), MediaContent(service: .spotify, id: "5bGNsC7FTQ3WZzz0XYOmvZ", type: .track, location: spotifyTrackURL))
    }

    func testParseAppleMusicURL() {
        let appleMusicPlaylistURL = URL(string: "https://music.apple.com/us/playlist/todays-hits/pl.f4d106fed2bd41149aaacabb233eb5eb")!
        XCTAssertEqual(sonosAPI.parse(url: appleMusicPlaylistURL), MediaContent(service: .apple, id: "pl.f4d106fed2bd41149aaacabb233eb5eb", type: .playlist, location: appleMusicPlaylistURL))

        let appleMusicAlbumURL = URL(string: "https://music.apple.com/us/album/guts/1694386825")!
        XCTAssertEqual(sonosAPI.parse(url: appleMusicAlbumURL), MediaContent(service: .apple, id: "1694386825", type: .album, location: appleMusicAlbumURL))

        let appleMusicArtistURL = URL(string: "https://music.apple.com/us/artist/olivia-rodrigo/979458609")!
        XCTAssertEqual(sonosAPI.parse(url: appleMusicArtistURL), MediaContent(service: .apple, id: "979458609", type: .artist, location: appleMusicArtistURL))

        let appleMusicSongURL = URL(string: "https://music.apple.com/us/album/vampire/1694386825?i=1694386830")!
        XCTAssertEqual(sonosAPI.parse(url: appleMusicSongURL), MediaContent(service: .apple, id: "1694386830", type: .track, location: appleMusicSongURL))
    }
    
    func testPlaylist() {
        let zone = Bundle.module.url(forResource: "sonos-hos-playlist", withExtension: "xml")
        let zoneXML = try! String(contentsOf: zone!)
        let playlists = PlaylistParser().parsePlaylistsTracks(IP: "192.192.2", xml: zoneXML)
        print(playlists)
        let names = playlists.map(\.title)
        print(names)
    }
}
