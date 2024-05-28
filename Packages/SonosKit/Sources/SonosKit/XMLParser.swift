import Foundation
import SWXMLHash

final class XMLParserSonos {

    func parse(xml: String) {
        let xml = XMLHash.parse(xml)
        let zones = xml["s:Envelope"]["s:Body"]["u:GetZoneGroupStateResponse"]["ZoneGroupState"]["ZoneGroupState"]["ZoneGroups"]["ZoneGroup"]
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
        guard let zonesParsed: [ZoneGroup] = try? zones.value() else { return [] }
        return zonesParsed
    }

    func parseVanishedDevices(xml: String) -> [VanishedDevice] {
        let xmlParsed = XMLHash.parse(xml)
        let vanishedDevices = xmlParsed["s:Envelope"]["s:Body"]["u:GetZoneGroupStateResponse"]["ZoneGroupState"]["ZoneGroupState"]["VanishedDevices"]
        let items = vanishedDevices.children
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"

        return items.compactMap { item in
            guard let id = item.element?.attribute(by: "UUID")?.text else { return nil }
            let name = item.element?.attribute(by: "ZoneName")?.text
            let lastKnownIP = item.element?.attribute(by: "LastKnownIP")?.text
            let date = dateFormatter.date(from: item.element?.attribute(by: "LastSeenUTC")?.text ?? "")
            let reason = item.element?.attribute(by: "Reason")?.text
            let info = item.element?.attribute(by: "MoreInfo")?.text
            let macAddress = item.element?.attribute(by: "Mac")?.text

            return VanishedDevice(id: id, name: name, reason: reason, IP: lastKnownIP, lastSeen: date, info: info, macAddress: macAddress)
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

    func parsePositionInfo(xml: String, IP: String, preferredIPForTrackAlbumArt: String?) -> Track? {
        var xml = xml
        if xml.contains("&gt") {
            xml = xml.unescaped
        }
        let xmlParsed = XMLHash.parse(xml)

        // Check for TV
        if let trackURI = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackURI"].element?.text, trackURI.contains("htastream") {
            return Track(trackID: "")
        }

        // Check for Radio
        if let radioText = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["r:streamContent"].element?.text, !radioText.isEmpty {
            let (title, album, artist) = parseRadioTrackInfo(information: radioText)
            let trackURI = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackURI"].element?.text
            let contentType = ContentType(xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["upnp:class"].element?.text ?? "")

            return Track(
                trackID: trackURI ?? "",
                name: title,
                artist: artist,
                album: album,
                musicService: .unknown,
                metadata: Track.Metadata(ISRC: nil, openInURL: nil, contentType: contentType)
            )
        }

        guard let trackDurationString = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackDuration"].element?.text,
              let trackURI = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackURI"].element?.text,
              !trackURI.isEmpty,
              let trackNumber = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["Track"].element?.text
        else {
            return .empty
        }

        let name = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["dc:title"].element?.text ?? "Unknown"
        let album = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["upnp:album"].element?.text
        let artist = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["dc:creator"].element?.text
        let albumArtist = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["r:albumArtist"].element?.text

        let contentType = ContentType(xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["upnp:class"].element?.text ?? "")

        let releaseDate = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["r:releaseDate"].element?.text

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

        if trackURI.contains("x-file-cifs") {
            musicService = .library
        }

        // TODO: Add hi res icon
//        print(item["res"].element?.attribute(by: "protocolInfo")?.text.removingPercentEncoding)
        var trackID = ""
        let tidalPattern = #/track\/(\d{7,9})/#
        if let trackURIRemovePercent = trackURI.removingPercentEncoding, let result = try? tidalPattern.firstMatch(in: trackURIRemovePercent) {
            musicService = .tidal
            trackID = String(result.1)
        }

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
        case .library:
            trackID = trackURI
        case .plex:
            trackID = trackURI
        case .tidal:
            break
//            trackID = trackURI
        }

        var sonosAlbumArtURL: URL? = nil
        if let albumArtURI = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["upnp:albumArtURI"].all.first?.element?.text {
            let ip = preferredIPForTrackAlbumArt ?? IP
            sonosAlbumArtURL = URL(string: "http://\(ip):1400\(albumArtURI.unescaped)")

            if sonosAlbumArtURL == nil {
                sonosAlbumArtURL = URL(string: albumArtURI.unescaped)
                // MARK: Upscale
                if let sonosAlbumArt = sonosAlbumArtURL?.absoluteString {
                    let modified = sonosAlbumArt.replacingOccurrences(of: "w=\\d+", with: "w=\(800)", options: .regularExpression)
                    if let upscaledURL = URL(string: modified) {
                        sonosAlbumArtURL = upscaledURL
                    }
                }
            }
        }

        return Track(trackID: trackID, name: name, artist: albumArtist ?? (artist ?? ""), album: album ?? "", musicService: musicService, duration: trackDuration, playbackPosition: playbackPosition, position: Int(trackNumber) ?? 0, sonosAlbumArtURL: sonosAlbumArtURL)
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

    func parseMediaInfo(xml: String) -> PlaybackService {
        let xmlParsed = XMLHash.parse(xml)
        guard let currentURI = xmlParsed["s:Envelope"]["s:Body"]["u:GetMediaInfoResponse"]["CurrentURI"].element?.text else {
            return .unknown
        }

        if currentURI.contains("htastream") {
            return .tv
        }

        if currentURI.contains("radio") {
            return .radio
        }

        if currentURI.contains("airplay") {
            return .airplay
        }

        if currentURI.contains("queue") {
            return .queue
        }

        if currentURI.contains("spotify") {
            return .spotifyConnect
        }

        // TODO: Figure out
        if currentURI.contains("line-in") {
            return .lineIn
        }

        return .unknown
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

    func parseGetCrossfade(xml: String) -> Bool? {
        let xmlParsed = XMLHash.parse(xml)
        guard let isCrossfadeEnabled = xmlParsed["s:Envelope"]["s:Body"]["u:GetCrossfadeModeResponse"]["CrossfadeMode"].element?.text else {
            return nil
        }
        return isCrossfadeEnabled == "1"
    }

    func parseHouseID(xml: String) -> String {
        let xmlParsed = XMLHash.parse(xml)
        guard let householdID = xmlParsed["s:Envelope"]["s:Body"]["u:GetZoneGroupAttributesResponse"]["CurrentMuseHouseholdId"].element?.text
        else {
            return ""
        }
        return householdID
    }

    func parseSleepTimer(xml: String) -> Date? {
        let xmlParsed = XMLHash.parse(xml)
        guard let sleepTimeRemaining = xmlParsed["s:Envelope"]["s:Body"]["u:GetRemainingSleepTimerDurationResponse"]["RemainingSleepTimerDuration"].element?.text else {
            return nil
        }

        var trackDuration = Duration.zero
        let trackDurationComponents = sleepTimeRemaining.components(separatedBy: ":")
        if trackDurationComponents.count == 3, let hours = Int(trackDurationComponents[0]), let minutes = Int(trackDurationComponents[1]), let seconds = Int(trackDurationComponents[2]) {
            let totalSeconds = (hours * 60 * 60) + (minutes * 60) + seconds
            trackDuration = Duration.seconds(totalSeconds)
        }

        if trackDuration != .zero {
            return Date.now.addingTimeInterval(Double(trackDuration.components.seconds))
        }

        return nil
    }

    func parseQueue(IP: String, xml: String, preferredIPForTrackAlbumArt: String?) -> [Track] {
        let xmlParsed = XMLHash.parse(xml)
        guard let resultXML = xmlParsed["s:Envelope"]["s:Body"]["u:BrowseResponse"]["Result"].element?.innerXML else { return []}
        let resultsParsed = XMLHash.parse(resultXML)
        guard let items = resultsParsed.children.first?.children else { return [] }
        var tracks: [Track] = []

   
        for item in items {
            guard let trackNumber = Int(item.element?.attribute(by: "id")?.text.components(separatedBy: "/").last ?? "")
            else {
                continue
            }

            let title = item["dc:title"].element?.text ?? "Unknown"
            let albumArtist = item["r:albumArtist"].element?.text
            var trackDuration = TimeInterval.zero
            if let trackDurationString = item["res"].element?.attribute(by: "duration")?.text {
                let trackDurationComponents = trackDurationString.components(separatedBy: ":")
                if trackDurationComponents.count == 3,
                   let hours = Int(trackDurationComponents[0]),
                   let minutes = Int(trackDurationComponents[1]),
                   let seconds = Int(trackDurationComponents[2])
                {
                    let totalMilliseconds = ((hours * 60 + minutes) * 60 + seconds) * 1000
                    trackDuration = TimeInterval(totalMilliseconds)
                }
            }

            var trackID = title
            var musicService: MusicService = .unknown

            if let trackURI = item["res"].element?.text.removingPercentEncoding {
                musicService = trackURI.contains("spotify") ? .spotify : .apple
                if trackURI.contains("airplay") {
                    musicService = .airplay
                }

                if trackURI.contains("x-file-cifs") {
                    musicService = .library
                }

                // TODO: Parse with this for HiRes info
//                print(item["res"].element?.attribute(by: "protocolInfo")?.text.removingPercentEncoding)
//                if protocolInfo.contains("x-sonos-http") {
//                    musicService = .plex
//                }

                let tidalPattern = #/track\/(\d{7,9})/#
                if let trackURIRemovePercent = trackURI.removingPercentEncoding, let result = try? tidalPattern.firstMatch(in: trackURIRemovePercent) {
                    musicService = .tidal
                    trackID = String(result.1)
                }

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
                case .library:
                    trackID = item["res"].element?.text ?? ""
                case .plex:
                    // MARK: Verify
                    trackID = item["res"].element?.text ?? ""
                case .tidal:
                    break
                }
            }

            let artist = item["dc:creator"].element?.text
            var sonosAlbumArtURL: URL?
            if let albumArtURI = item["upnp:albumArtURI"].all.first?.element?.text {
                let ip = preferredIPForTrackAlbumArt ?? IP
                sonosAlbumArtURL = URL(string: "http://\(ip):1400\(albumArtURI.unescaped)")

                if sonosAlbumArtURL == nil {
                    sonosAlbumArtURL = URL(string: albumArtURI.unescaped)
                    // MARK: Upscale
                    if let sonosAlbumArt = sonosAlbumArtURL?.absoluteString {
                        let modified = sonosAlbumArt.replacingOccurrences(of: "w=\\d+", with: "w=\(800)", options: .regularExpression)
                        if let upscaledURL = URL(string: modified) {
                            sonosAlbumArtURL = upscaledURL
                        }
                    }
                }
            }

            var emptyArtist = ""
            if let albumArtist {
                emptyArtist = albumArtist
            } else if let artist {
                emptyArtist = artist
            }

            var emptyAlbum = ""
            if let album = item["upnp:album"].element?.text {
                emptyAlbum = album
            }

            let track = Track(
                trackID: trackID,
                name: title,
                artist: emptyArtist,
                album: emptyAlbum,
                musicService: musicService,
                duration: trackDuration,
                playbackPosition: .zero,
                position: trackNumber,
                sonosAlbumArtURL: sonosAlbumArtURL
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

    func parseLibrarySearch(IP: String, xml: String) -> [PlayableContent] {
        let xmlParsed = XMLHash.parse(xml)
        guard let resultXML = xmlParsed["s:Envelope"]["s:Body"]["u:BrowseResponse"]["Result"].element?.innerXML else { return []}
        let resultsParsed = XMLHash.parse(resultXML)
        guard let items = resultsParsed.children.first?.children else { return [] }

        var searchResults: [PlayableContent] = []

        for item in items {
            guard let title = item["dc:title"].element?.text,
                  let trackID = item["res"].element?.text,
                  let type = item["upnp:class"].element?.text,
                  let contentType = ContentType(type) else {
                continue
            }


            var artist = ""

            let album = item["upnp:album"].element?.text
            let trackAlbumArtist = item["r:albumArtist"].element?.text
            let creator = item["dc:creator"].element?.text
            let albumID = item.element?.allAttributes["parentID"]?.text

            var sonosAlbumArtURL: URL?
            if let albumArtURI = item["upnp:albumArtURI"].all.first?.element?.text {
                sonosAlbumArtURL = URL(string: "http://\(IP):1400\(albumArtURI.unescaped)")
            }

            var subtitle = ""
            switch contentType {
            case .album:
                artist = creator ?? ""
                subtitle = "\(artist)"
            case .track:
                artist = (trackAlbumArtist ?? creator) ?? ""
                if let album {
                    subtitle = "\(artist) • \(album)"
                }
            default:
                break
            }

            let mediaContent = MediaContent(service: .library, id: trackID, type: contentType, location: nil)
            let metadata = PlayableContentMetadata(artist: artist, album: album, albumID: albumID)
            let playableContent = PlayableContent(title: title, subtitle: subtitle, artwork: sonosAlbumArtURL, content: mediaContent, metadata: metadata)
            searchResults.append(playableContent)
        }

        return searchResults
    }

    func parsePlaylists(IP: String, xml: String) -> [PlayableContent] {
        let xmlParsed = XMLHash.parse(xml)
        guard let resultXML = xmlParsed["s:Envelope"]["s:Body"]["u:BrowseResponse"]["Result"].element?.innerXML else { return []}
        let resultsParsed = XMLHash.parse(resultXML)
        guard let items = resultsParsed.children.first?.children else { return [] }

        var searchResults: [PlayableContent] = []

        for item in items {
            guard let title = item["dc:title"].element?.text,
                  let trackID = item["res"].element?.text,
                  let type = item["upnp:class"].element?.text,
                  let contentType = ContentType(type) else {
                continue
            }


            var artist = ""

            let album = item["upnp:album"].element?.text
            let trackAlbumArtist = item["r:albumArtist"].element?.text
            let creator = item["dc:creator"].element?.text
            let albumID = item.element?.allAttributes["parentID"]?.text
            var sonosAlbumArtURL: URL?
            if let albumArtURI = item["upnp:albumArtURI"].all.first?.element?.text {
                sonosAlbumArtURL = URL(string: "http://\(IP):1400\(albumArtURI.unescaped)")
            }

            var subtitle = ""
            switch contentType {
            case .album:
                artist = creator ?? ""
                subtitle = "\(artist)"
            case .track:
                artist = (trackAlbumArtist ?? creator) ?? ""
                if let album {
                    subtitle = "\(artist) • \(album)"
                }
            default:
                break
            }

            let mediaContent = MediaContent(service: .library, id: trackID, type: contentType, location: nil)
            let metadata = PlayableContentMetadata(artist: artist, album: album, albumID: albumID)
            let playableContent = PlayableContent(title: title, subtitle: subtitle, artwork: sonosAlbumArtURL, content: mediaContent, metadata: metadata)
            searchResults.append(playableContent)
        }

        return searchResults
    }

    func parsePlaylistsTracks(IP: String, xml: String) -> [PlayableContent] {
        let xmlParsed = XMLHash.parse(xml)
        guard let resultXML = xmlParsed["s:Envelope"]["s:Body"]["u:BrowseResponse"]["Result"].element?.innerXML else { return []}
        let resultsParsed = XMLHash.parse(resultXML)
        guard let items = resultsParsed.children.first?.children else { return [] }

        var searchResults: [PlayableContent] = []

        for item in items {
            guard let title = item["dc:title"].element?.text,
                  var trackID = item["res"].element?.text,
                  let type = item["upnp:class"].element?.text,
                  let contentType = ContentType(type) else {
                continue
            }


            var artist = ""

            let album = item["upnp:album"].element?.text
            let trackAlbumArtist = item["r:albumArtist"].element?.text
            let creator = item["dc:creator"].element?.text
            let albumID = item.element?.allAttributes["parentID"]?.text
            var sonosAlbumArtURL: URL?
            if let albumArtURI = item["upnp:albumArtURI"].all.first?.element?.text {
                sonosAlbumArtURL = URL(string: "http://\(IP):1400\(albumArtURI.unescaped)")
            }

            var subtitle = ""
            switch contentType {
            case .album:
                artist = creator ?? ""
                subtitle = "\(artist)"
            case .track:
                artist = (trackAlbumArtist ?? creator) ?? ""
                if let album {
                    subtitle = "\(artist) • \(album)"
                }
            default:
                break
            }

            var musicService = MusicService.unknown
            if let trackURI = item["res"].element?.text.removingPercentEncoding {
                musicService = trackURI.contains("spotify") ? .spotify : .apple
                if trackURI.contains("airplay") {
                    musicService = .airplay
                }

                if trackURI.contains("x-file-cifs") {
                    musicService = .library
                }

                // TODO: Parse with this for HiRes info
//                print(item["res"].element?.attribute(by: "protocolInfo")?.text.removingPercentEncoding)
//                if protocolInfo.contains("x-sonos-http") {
//                    musicService = .plex
//                }

                let tidalPattern = #/track\/(\d{7,9})/#
                if let trackURIRemovePercent = trackURI.removingPercentEncoding, let result = try? tidalPattern.firstMatch(in: trackURIRemovePercent) {
                    musicService = .tidal
                    trackID = String(result.1)
                }

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
                case .library:
                    trackID = item["res"].element?.text ?? ""
                case .plex:
                    // MARK: Verify
                    trackID = item["res"].element?.text ?? ""
                case .tidal:
                    break
                }
            }

            var trackDuration = Duration.zero
            if let trackDurationString = item["res"].element?.attribute(by: "duration")?.text {
                let trackDurationComponents = trackDurationString.components(separatedBy: ":")
                if trackDurationComponents.count == 3,
                   let hours = Int(trackDurationComponents[0]),
                   let minutes = Int(trackDurationComponents[1]),
                   let seconds = Int(trackDurationComponents[2])
                {
                    let totalMilliseconds = ((hours * 60 + minutes) * 60 + seconds) * 1000
                    trackDuration = Duration.milliseconds(totalMilliseconds)
                }
            }

            let mediaContent = MediaContent(service: musicService, id: trackID, type: contentType, location: nil)
            let metadata = PlayableContentMetadata(duration: trackDuration, artist: artist, album: album, albumID: albumID)
            let playableContent = PlayableContent(title: title, subtitle: subtitle, artwork: sonosAlbumArtURL, content: mediaContent, metadata: metadata)
            searchResults.append(playableContent)
        }

        return searchResults
    }

    func parseGetUpdateId(IP: String, xml: String) -> String {
        let xmlParsed = XMLHash.parse(xml)
        let updateID = xmlParsed["s:Envelope"]["s:Body"]["u:BrowseResponse"]["UpdateID"].element?.text
        return updateID ?? "0"
    }

    func parseDeviceInfo(xml: String) -> DeviceInfo? {
        let xmlParsed = XMLHash.parse(xml)
        let deviceXML = xmlParsed["root"]["device"]

        guard let modelName = deviceXML["modelName"].element?.text,
              let modelNumber = deviceXML["modelNumber"].element?.text,
              let manufacturer = deviceXML["manufacturer"].element?.text,
              let seriesID = deviceXML["seriesid"].element?.text else { return nil }

        return DeviceInfo(
            modelName: modelName,
            modelNumber: modelNumber,
            seriesID: seriesID,
            manufacturer: manufacturer
        )
    }

    // MARK: Alarm Clock
    func parseAlarmClockList(from xml: String) -> [Alarm] {
        let xmlParsed = XMLHash.parse(xml)
        guard let resultXML = xmlParsed["s:Envelope"]["s:Body"]["u:ListAlarmsResponse"]["CurrentAlarmList"].element?.innerXML else { return [] }
        let resultsParsed = XMLHash.parse(resultXML)
        guard let items = resultsParsed.children.first?.children else { return [] }

        var alarms: [Alarm] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "hh:mm:ss"

        for item in items {
            guard let id = item.element?.attribute(by: "ID")?.text,
                  let roomUUID = item.element?.attribute(by: "RoomUUID")?.text,
                  let startTime = item.element?.attribute(by: "StartTime")?.text,
                  let duration = item.element?.attribute(by: "Duration")?.text,
                  let recurrence = item.element?.attribute(by: "Recurrence")?.text,
                  let enabled = item.element?.attribute(by: "Enabled")?.text,
                  let programURI = item.element?.attribute(by: "ProgramURI")?.text,
                  let programMetaData = item.element?.attribute(by: "ProgramMetaData")?.text,
                  let includeLinkedZones = item.element?.attribute(by: "IncludeLinkedZones")?.text,
                  let volume = item.element?.attribute(by: "Volume")?.text,
                  let playMode = item.element?.attribute(by: "PlayMode")?.text
            else {
                continue
            }

            var day = Calendar.current.startOfDay(for: .now)
            let startTimeComponents = startTime.components(separatedBy: ":")
            if startTimeComponents.count == 3, let hours = Int(startTimeComponents[0]), let minutes = Int(startTimeComponents[1]), let seconds = Int(startTimeComponents[2]) {
                let totalSeconds = (hours * 60 * 60) + (minutes * 60) + seconds
                day.addTimeInterval(Double(totalSeconds))
            }

            var alarmDuration = Duration.zero
            let trackDurationComponents = duration.components(separatedBy: ":")
            if trackDurationComponents.count == 3, let hours = Int(trackDurationComponents[0]), let minutes = Int(trackDurationComponents[1]), let seconds = Int(trackDurationComponents[2]) {
                let totalSeconds = (hours * 60 * 60) + (minutes * 60) + seconds
                alarmDuration = Duration.seconds(totalSeconds)
            }

            let alarm = Alarm(
                id: id,
                roomID: roomUUID,
                enabled: enabled == "1",
                startTime: day,
                duration: alarmDuration,
                schedule: Frequency(mode: recurrence),
                programURI: programURI,
                programMetaData: programMetaData,
                volume: Double(volume) ?? 0,
                includeLinkedZones: includeLinkedZones == "1",
                playMode: PlayMode(mode: playMode) ?? .normal,
                scheduleRaw: recurrence,
                shuffle: playMode == "SHUFFLE"
            )
            alarms.append(alarm)
        }
        return alarms
    }

    func parseAlarmClockInfo(uri: String, metadataXML: String?) -> PlayableContent? {
        guard var metadataXML, !metadataXML.isEmpty else {
            return PlayableContent(
                title: "Sonos Chime",
                subtitle: "",
                artwork: nil,
                content: MediaContent(
                    service: .unknown,
                    id: uri,
                    type: .track,
                    location: nil
                ),
                metadata: nil
            )
        }
        if metadataXML.contains("&gt") {
            metadataXML = metadataXML.unescaped
        }
        let xmlParsed = XMLHash.parse(metadataXML)

        guard let id = xmlParsed["DIDL-Lite"]["item"].element?.attribute(by: "id")?.text,
              let name = xmlParsed["DIDL-Lite"]["item"]["dc:title"].element?.text,
              let type = xmlParsed["DIDL-Lite"]["item"]["upnp:class"].element?.text,
              let contentType = ContentType(type)
        else {
            return nil
        }

        return PlayableContent(
            title: name,
            subtitle: "",
            artwork: nil,
            content: MediaContent(
                service: .unknown,
                id: uri,
                type: contentType,
                location: nil
            ),
            metadata: nil
        )
    }

    private func parseRadioTrackInfo(information: String) -> (String, String, String){
        var details = [String: String]()

        // Split the input string into key-value pairs
        let pairs = information.split(separator: "|")

        // Iterate over each pair and split into key and value
        for pair in pairs {
            if let index = pair.firstIndex(of: " ") {
                let key = String(pair[..<index])
                let value = String(pair[pair.index(after: index)...])
                details[key] = value
            }
        }

        var foundTitle = ""
        var foundAlbum = ""
        var foundArtist = ""
        
        // Accessing the parsed details
        if let title = details["TITLE"]?.trimmingCharacters(in: .whitespacesAndNewlines), title != "undefined" {
            foundTitle = title
        }
        if let artist = details["ARTIST"]?.trimmingCharacters(in: .whitespacesAndNewlines), artist != "undefined" {
            foundArtist = artist
        }
        if let album = details["ALBUM"]?.trimmingCharacters(in: .whitespacesAndNewlines), album != "undefined" {
            foundAlbum = album
        }

        if foundTitle.isEmpty {
            return (information, "", "")
        }
        return (foundTitle, foundAlbum, foundArtist)
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

    var encodeForSonos: String {
        let xml = self
        return xml
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: " ", with: "&#32;")
    }

    var encodeProgramURI: String {
        let xml = self
        return xml
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
