import Foundation
import SWXMLHash

final class XMLParserSonos {

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

    func parseVolume(xml: String) throws -> Int {
        let xml = XMLHash.parse(xml)
        guard let volume = xml["s:Envelope"]["s:Body"]["u:GetVolumeResponse"]["CurrentVolume"].element?.text, let volumeParsed = Int(volume) else {
            throw XMLParserSonosError.parsing
        }
        return volumeParsed
    }

    func parseGroupVolume(xml: String) throws -> Int {
        let xml = XMLHash.parse(xml)
        guard let volume = xml["s:Envelope"]["s:Body"]["u:GetGroupVolumeResponse"]["CurrentVolume"].element?.text, let volumeParsed = Int(volume) else {
            throw XMLParserSonosError.parsing
        }
        return volumeParsed
    }

    func parseZones(xml: String) -> [ZoneGroup] {
        let xmlParsed = XMLHash.parse(xml)
        let zones = xmlParsed["s:Envelope"]["s:Body"]["u:GetZoneGroupStateResponse"]["ZoneGroupState"]["ZoneGroupState"]["ZoneGroups"]["ZoneGroup"]
        let zonesParsed: [ZoneGroup] = try! zones.value()
        return zonesParsed
    }

    func parseVanishedDevices(xml: String) -> [VanishedDevice] {
        let xmlParsed = XMLHash.parse(xml)
        let vanishedDevices = xmlParsed["s:Envelope"]["s:Body"]["u:GetZoneGroupStateResponse"]["ZoneGroupState"]["ZoneGroupState"]["VanishedDevices"]
        print(vanishedDevices)
        let items = vanishedDevices.children
        print(items)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"

        return items.compactMap { item in
            guard let id = item.element?.attribute(by: "UUID")?.text else { return nil }
            let name = item.element?.attribute(by: "ZoneName")?.text
            let lastKnownIP = item.element?.attribute(by: "LastKnownIP")?.text
            let date = dateFormatter.date(from: item.element?.attribute(by: "LastSeenUTC")?.text ?? "")
            let reason = item.element?.attribute(by: "Reason")?.text

            return VanishedDevice(id: id, name: name, reason: reason, IP: lastKnownIP, lastSeen: date)
        }
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

    func parsePositionInfo(xml: String, IP: String) -> Track? {
        var xml = xml
        if xml.contains("&gt") {
            xml = xml.unescaped
        }
        let xmlParsed = XMLHash.parse(xml)

        // Check for TV
        if let trackURI = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackURI"].element?.text, trackURI.contains("htastream") {
            return Track(trackID: "", TVMode: true)
        }

        guard let name = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["dc:title"].element?.text,
              let artist = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["dc:creator"].element?.text,
              let trackDurationString = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackDuration"].element?.text,
              let albumArtURI = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["upnp:albumArtURI"].element?.text,
              let trackURI = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackURI"].element?.text,
              let trackNumber = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["Track"].element?.text
        else {
            return nil
        }

        let album = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["upnp:album"].element?.text

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
            trackDuration = TimeInterval(totalMilliseconds)
        }

        var musicService: MusicService = trackURI.contains("spotify") ? .spotify : .apple
        if trackURI.contains("airplay") {
            musicService = .airplay
        }

        var trackID = ""
        switch musicService {
        case .apple:
            let pattern = #/song:(\w*)/#
            if let trackURIRemovePercent = trackURI.removingPercentEncoding, let result = try? pattern.firstMatch(in: trackURIRemovePercent) {
                trackID = String(result.1)
            } else {
                musicService = .unknown
            }
        case .spotify:
            if let trackInfo = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["res"].element?.text.removingPercentEncoding {
                let pattern = #/track:(\w*)/#
                if let result = try? pattern.firstMatch(in: trackInfo) {
                    trackID = String(result.1)
                } else {
                    musicService = .unknown
                }
            } else {
                musicService = .unknown
            }
        case .airplay, .unknown:
            break
        }

        var sonosAlbumArtURL = URL(string: "http://\(IP):1400\(albumArtURI.unescaped)")
        if sonosAlbumArtURL == nil {
            sonosAlbumArtURL = URL(string: albumArtURI.unescaped)
        }

        return Track(trackID: trackID, name: name, artist: artist, album: album ?? "", musicService: musicService, duration: trackDuration, playbackPosition: playbackPosition, position: Int(trackNumber) ?? 0, sonosAlbumArtURL: sonosAlbumArtURL, TVMode: false)
    }

    func parsePlaybackInfo(xml: String) -> PlaybackStatus {
        let xmlParsed = XMLHash.parse(xml)
        guard let status = xmlParsed["s:Envelope"]["s:Body"]["u:GetTransportInfoResponse"]["CurrentTransportState"].element?.text
        else {
            return .transitioning
        }
        if status == "PLAYING" {
            return .playing
        } else if status == "PAUSED_PLAYBACK" || status == "STOPPED" {
            return .paused
        }

        return .transitioning
    }

    func parseMediaInfo(xml: String) -> Bool {
        let xmlParsed = XMLHash.parse(xml)
        guard let currentURI = xmlParsed["s:Envelope"]["s:Body"]["u:GetMediaInfoResponse"]["CurrentURI"].element?.text
        else {
            return false
        }
        return currentURI.contains("htastream")
    }

    func parseGetCurrentTransportActions(xml: String) -> AvailableActions? {
        let xmlParsed = XMLHash.parse(xml)
        guard let parseGetCurrentTransportActions = xmlParsed["s:Envelope"]["s:Body"]["u:GetCurrentTransportActionsResponse"]["Actions"].element?.text else {
            return nil
        }
        let actions = parseGetCurrentTransportActions.components(separatedBy: ",")
        let availableActions = AvailableActions(actions.compactMap(AvailableActions.init))
        return availableActions
    }

    func parsePlaybackMode(_ xml: String) -> PlayMode? {
        let xmlParsed = XMLHash.parse(xml)
        guard let mode = xmlParsed["s:Envelope"]["s:Body"]["u:GetTransportSettingsResponse"]["PlayMode"].element?.text else {
            return nil
        }
        return PlayMode(mode: mode)
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

        return Double(masterVolume) ?? 0

    }

    func parseGetGroupMute(xml: String) -> Bool? {
        let xmlParsed = XMLHash.parse(xml)
        guard let isMuted = xmlParsed["s:Envelope"]["s:Body"]["u:GetGroupMuteResponse"]["CurrentMute"].element?.text else {
            return nil
        }
        return isMuted == "1"
    }

    func parseGetRoomMute(xml: String) -> Bool? {
        let xmlParsed = XMLHash.parse(xml)
        guard let isMuted = xmlParsed["s:Envelope"]["s:Body"]["u:GetMuteResponse"]["CurrentMute"].element?.text else {
            return nil
        }
        return isMuted == "1"
    }

    func parseHouseID(xml: String) -> String {
        let xmlParsed = XMLHash.parse(xml)
        guard let householdID = xmlParsed["s:Envelope"]["s:Body"]["u:GetZoneGroupAttributesResponse"]["CurrentMuseHouseholdId"].element?.text
        else {
            return ""
        }
        return householdID
    }

    func parseQueue(IP: String, xml: String) -> [Track] {
        let xmlParsed = XMLHash.parse(xml)
        guard let resultXML = xmlParsed["s:Envelope"]["s:Body"]["u:BrowseResponse"]["Result"].element?.innerXML else { return []}
        let resultsParsed = XMLHash.parse(resultXML)
        guard let items = resultsParsed.children.first?.children else { return [] }
        var tracks: [Track] = []

   
        for item in items {
            guard let title = item["dc:title"].element?.text,
                  let artist = item["dc:creator"].element?.text,
                  let album = item["upnp:album"].element?.text,
                  let trackDurationString = item["res"].element?.attribute(by: "duration")?.text,
                  let trackURI = item["res"].element?.text.removingPercentEncoding,
                  let albumArtURI = item["upnp:albumArtURI"].element?.text,
                  let trackNumber = Int(item.element?.attribute(by: "id")?.text.components(separatedBy: "/").last ?? "")
            else {
                continue
            }

            var trackDuration = TimeInterval.zero
            let trackDurationComponents = trackDurationString.components(separatedBy: ":")
            if trackDurationComponents.count == 3,
               let hours = Int(trackDurationComponents[0]),
               let minutes = Int(trackDurationComponents[1]),
               let seconds = Int(trackDurationComponents[2])
            {
                let totalMilliseconds = ((hours * 60 + minutes) * 60 + seconds) * 1000
                trackDuration = TimeInterval(totalMilliseconds)
            }

            var musicService: MusicService = trackURI.contains("spotify") ? .spotify : .apple
            if trackURI.contains("airplay") {
                musicService = .airplay
            }

            var trackID = ""
            switch musicService {
            case .apple:
                let pattern = #/song:(\w*)/#
                if let trackURIRemovePercent = trackURI.removingPercentEncoding, let result = try? pattern.firstMatch(in: trackURIRemovePercent) {
                    trackID = String(result.1)
                } else {
                    musicService = .unknown
                }
            case .spotify:
                let pattern = #/track:(\w*)/#
                if let result = try? pattern.firstMatch(in: trackURI) {
                    trackID = String(result.1)
                } else {
                    musicService = .unknown
                }
            case .airplay, .unknown:
                musicService = .unknown
            }

            var sonosAlbumArtURL = URL(string: "http://\(IP):1400\(albumArtURI.unescaped)")
            if sonosAlbumArtURL == nil {
                sonosAlbumArtURL = URL(string: albumArtURI.unescaped)
            }

            let track = Track(
                trackID: trackID,
                name: title,
                artist: artist,
                album: album,
                musicService: musicService,
                duration: trackDuration,
                playbackPosition: .zero,
                position: trackNumber,
                sonosAlbumArtURL: sonosAlbumArtURL,
                TVMode: false
            )

            tracks.append(track)
        }
        return tracks
    }

    func parseForCurrentValue(xml: String) throws -> Bool {
        // Parse out CurrentValue
        let pattern = "<CurrentValue>(.*?)</CurrentValue>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)

            if let match = regex.firstMatch(in: xml, options: [], range: range) {
                let valueRange = match.range(at: 1)
                if let valueRange = Range(valueRange, in: xml) {
                    let value = String(xml[valueRange])
                    return value == "1"
                }
            }
        }
        throw XMLParserSonosError.parsing
    }

    func parseForHTAudioIn(xml: String) throws -> AudioInputFormat {
        // Parse out CurrentValue
        let pattern = "<HTAudioIn>(.*?)</HTAudioIn>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)

            if let match = regex.firstMatch(in: xml, options: [], range: range) {
                let valueRange = match.range(at: 1)
                if let valueRange = Range(valueRange, in: xml) {
                    guard let value = Int(xml[valueRange]), let audioInputFormat = AudioInputFormat(rawValue: value) else {
                        return .unknown
                    }
                    return audioInputFormat
                }
            }
        }
        throw XMLParserSonosError.parsing
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

    var escaped: String {
        var xml = self
        xml = xml.replacingOccurrences(of: "&", with: "&amp;")
        xml = xml.replacingOccurrences(of: "<", with: "&lt;")
        xml = xml.replacingOccurrences(of: ">", with: "&gt;")
        return xml
    }

    var xmlAllowedString: String {
        var xml = self
        xml = xml.replacingOccurrences(of: " ", with: "&#32;")
        return xml
    }
}
