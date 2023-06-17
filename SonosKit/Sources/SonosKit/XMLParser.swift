import Foundation
import SWXMLHash

class XMLParserSonos {

    func unescape(xml: String) {
        let unescaped = xml.unescaped
        print(unescaped)
    }

    func parse(xml: String) {
        let xml = XMLHash.parse(xml)
        let zones = xml["s:Envelope"]["s:Body"]["u:GetZoneGroupStateResponse"]["ZoneGroupState"]["ZoneGroupState"]["ZoneGroups"]["ZoneGroup"]

        print(zones)


        let zonesParsed: [ZoneGroup] = try! zones.value()
        print(zonesParsed)

        let groups = zones[0].filterChildren { elem, index in
            elem.name == "ZoneGroupMember"
        }.children

        print(groups)

        let member: [ZoneGroupMember] = try! groups[0].value()
        print(member)


        print(zones["ZoneGroupMember"].description)

        let allRooms = zonesParsed.flatMap { zoneGroup in
           zoneGroup.zoneGroupMembers.compactMap {
                if !$0.invisible {
                    return Room(UUID: $0.UUID, location: $0.location, zoneName: $0.zoneName)
                } else {
                    return nil
                }
            }
        }

        print(allRooms)

        print(zonesParsed)

        zonesParsed.forEach { zoneGroup in
            zoneGroup.zoneGroupMembers.forEach { zoneGroupMember in
                print(zoneGroupMember.zoneName)
            }
            print()
        }
    }

    func parseVolume(xml: String) -> Int {
        let xml = XMLHash.parse(xml)
        let volume = xml["s:Envelope"]["s:Body"]["u:GetVolumeResponse"]["CurrentVolume"].element?.text
        return Int(volume ?? "0")!
    }

    func parseRelativeVolume(xml: String) -> Int {
        let xml = XMLHash.parse(xml)
        let volume = xml["s:Envelope"]["s:Body"]["u:SetRelativeVolumeResponse"]["NewVolume"].element?.text
        return Int(volume ?? "0")!
    }

    func parseZones(xml: String) -> [ZoneGroup] {
        let xmlParsed = XMLHash.parse(xml)
        let zones = xmlParsed["s:Envelope"]["s:Body"]["u:GetZoneGroupStateResponse"]["ZoneGroupState"]["ZoneGroupState"]["ZoneGroups"]["ZoneGroup"]
        let zonesParsed: [ZoneGroup] = try! zones.value()
        return zonesParsed
    }

//    func parsePositionInfo(xml: String) -> String {
//        let xmlParsed = XMLHash.parse(xml)
//        let zones = xmlParsed["s:Envelope"]["s:Body"]["u:GetZoneGroupStateResponse"]["ZoneGroupState"]["ZoneGroupState"]["ZoneGroups"]["ZoneGroup"]
//        let zonesParsed: [ZoneGroup] = try! zones.value()
//        return zonesParsed
//    }

    func parseTrackInfo(xml: String) -> Track? {
        let xmlParsed = XMLHash.parse(xml)
        guard let trackInfo = xmlParsed["DIDL-Lite"]["item"]["dc:title"].element?.text,
              let artist = xmlParsed["DIDL-Lite"]["item"]["dc:creator"].element?.text,
              let album = xmlParsed["DIDL-Lite"]["item"]["upnp:album"].element?.text
        else {
            return nil
        }
        return Track(name: trackInfo, artist: artist, album: album)
    }

    func parsePositionInfo(xml: String) -> Track? {
        let xmlParsed = XMLHash.parse(xml)
        guard let name = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["dc:title"].element?.text,
              let artist = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["dc:creator"].element?.text,
              let album = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["upnp:album"].element?.text
        else {
            return nil
        }
        return Track(name: name, artist: artist, album: album)
    }

    func parsePlaybackInfo(xml: String) -> String {
        let xmlParsed = XMLHash.parse(xml)
        guard let name = xmlParsed["s:Envelope"]["s:Body"]["u:GetTransportInfoResponse"]["CurrentTransportState"].element?.text
        else {
            return ""
        }
        return name
    }

    func parseRendererControl(xml: String) -> Double {
        let xmlParsed = XMLHash.parse(xml)
        guard let rendererControlXML = xmlParsed["e:propertyset"]["e:property"]["LastChange"].element?.text
        else {
            return 0
        }

        let lastChangeXML = XMLHash.parse(rendererControlXML.unescaped)

        let masterChannelElement = lastChangeXML["Event"]["InstanceID"].filterChildren { elem, index in
            elem.allAttributes["channel"]?.text == "Master"
        }

        let masterVolume: String = masterChannelElement["Volume"].element?.allAttributes["val"]?.text ?? ""

        print(masterVolume)

        return Double(masterVolume) ?? 0

    }

    func parseAVTransport(xml: String) -> Double {
        let xmlParsed = XMLHash.parse(xml)
        guard let rendererControlXML = xmlParsed["e:propertyset"]["e:property"]["LastChange"].element?.text
        else {
            return 0
        }

        let lastChangeXML = XMLHash.parse(rendererControlXML.unescaped)

        let masterChannelElement = lastChangeXML["Event"]["InstanceID"].filterChildren { elem, index in
            elem.allAttributes["channel"]?.text == "Master"
        }

        let masterVolume: String = masterChannelElement["Volume"].element?.allAttributes["val"]?.text ?? ""

        print(masterVolume)

        return Double(masterVolume) ?? 0

    }
}


extension String {
    var unescaped: String {
        var xml = self
        xml = xml.replacingOccurrences(of: "&lt;", with: "<")
        xml = xml.replacingOccurrences(of: "&gt;", with: ">")
        xml = xml.replacingOccurrences(of: "&amp;", with: "&")
        xml = xml.replacingOccurrences(of: "&quot;", with: "\"")
        xml = xml.replacingOccurrences(of: "&apos;", with: "'")
        return xml
    }
}
