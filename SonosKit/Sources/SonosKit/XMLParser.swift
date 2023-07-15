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
                    return Room(id: $0.UUID, ip: $0.location, name: $0.zoneName)
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

    func parseGroupVolume(xml: String) -> Int {
        let xml = XMLHash.parse(xml)
        let volume = xml["s:Envelope"]["s:Body"]["u:GetGroupVolumeResponse"]["CurrentVolume"].element?.text
        return Int(volume ?? "0")!
    }

    func parseRelativeVolume(xml: String) -> Int {
        let xml = XMLHash.parse(xml)
        let volume = xml["s:Envelope"]["s:Body"]["u:SetRelativeVolumeResponse"]["NewVolume"].element?.text
        return Int(volume ?? "0")!
    }

    func parseGroupRelativeVolume(xml: String) -> Int {
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

    func parseZonesEvent(xml: String) -> [ZoneGroup] {
        let xmlParsed = XMLHash.parse(xml)
        let zones = xmlParsed["e:propertyset"]["e:property"][0]["ZoneGroupState"]["ZoneGroupState"]["ZoneGroups"]["ZoneGroup"]
        guard let zonesParsed: [ZoneGroup] = try? zones.value() else {
            return []
        }
        return zonesParsed
    }

//    func parsePositionInfo(xml: String) -> String {
//        let xmlParsed = XMLHash.parse(xml)
//        let zones = xmlParsed["s:Envelope"]["s:Body"]["u:GetZoneGroupStateResponse"]["ZoneGroupState"]["ZoneGroupState"]["ZoneGroups"]["ZoneGroup"]
//        let zonesParsed: [ZoneGroup] = try! zones.value()
//        return zonesParsed
//    }

//    func parseTrackInfo(xml: String) -> Track? {
//        let xmlParsed = XMLHash.parse(xml)
//        guard let trackInfo = xmlParsed["DIDL-Lite"]["item"]["dc:title"].element?.text,
//              let artist = xmlParsed["DIDL-Lite"]["item"]["dc:creator"].element?.text,
//              let album = xmlParsed["DIDL-Lite"]["item"]["upnp:album"].element?.text
//        else {
//            return nil
//        }
//        return Track(name: trackInfo, artist: artist, album: album)
//    }

    func parsePositionInfo(xml: String) -> Track? {
        let xmlParsed = XMLHash.parse(xml)
        guard let name = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["dc:title"].element?.text,
              let artist = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["dc:creator"].element?.text,
              let album = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["upnp:album"].element?.text,
              let trackDurationString = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackDuration"].element?.text,
              let trackURI = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackURI"].element?.text
        else {
            return nil
        }

        var playbackPosition = TimeInterval.zero
        // MARK: Parse out RelTime
        let pattern = "<RelTime>(.*?)</RelTime>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)

            if let match = regex.firstMatch(in: xml, options: [], range: range) {
                let valueRange = match.range(at: 1)
                if let valueRange = Range(valueRange, in: xml) {
                    let timeStamp = String(xml[valueRange])
                    let components = timeStamp.components(separatedBy: ":")
                    if components.count == 3,
                       let hours = Int(components[0]),
                       let minutes = Int(components[1]),
                       let seconds = Int(components[2])
                    {
                        let totalMilliseconds = ((hours * 60 + minutes) * 60 + seconds) * 1000
                        print(totalMilliseconds) // Output: 220000
                        playbackPosition = TimeInterval(totalMilliseconds)
                    }
                }
            }
        }

        var trackDuration = TimeInterval.zero
        let trackDurationComponents = trackDurationString.components(separatedBy: ":")
        if trackDurationComponents.count == 3,
           let hours = Int(trackDurationComponents[0]),
           let minutes = Int(trackDurationComponents[1]),
           let seconds = Int(trackDurationComponents[2])
        {
            let totalMilliseconds = ((hours * 60 + minutes) * 60 + seconds) * 1000
            print(totalMilliseconds) // Output: 220000
            trackDuration = TimeInterval(totalMilliseconds)
        }

        let musicService: MusicService = trackURI.contains("spotify") ? .spotify : .apple

        return Track(name: name, artist: artist, album: album, musicService: musicService, duration: trackDuration, playbackPosition: playbackPosition)
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
