import Foundation

final class XMLParserSonos {
    func parseVolume(xml: String) throws -> Int {
        let value = try parseValue(xml: xml, named: "CurrentVolume")
        return Int(value) ?? 0
    }

    func parseZones(xml: String) -> [ZoneGroup] {
        ZoneGroupStateParser().parse(xml: xml)
    }

    func parseVanishedDevices(xml: String) -> [VanishedDevice] {
        VanishedDevicesParser().parse(xml: xml)
    }

    func parsePositionInfo(xml: String, IP: String, preferredIPForTrackAlbumArt: String?) -> Track? {
        let track = SonosTrackParser.parse(xmlString: xml, ip: IP, preferredIP: preferredIPForTrackAlbumArt)
        return track
        
//        var xml = xml
//        if xml.contains("&gt") {
//            xml = xml.unescaped
//        }
//        let xmlParsed = parseXML(xml)
//
//        // Check for TV
//        if let trackURI = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackURI"].element?.text, trackURI.contains("htastream") {
//            return Track(trackID: "")
//        }
//
//        // Check for Radio
//        if let radioText = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["r:streamContent"].element?.text, !radioText.isEmpty {
//            let (title, album, artist) = parseRadioTrackInfo(information: radioText)
//            let trackURI = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackURI"].element?.text
//            let contentType = ContentType(xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["upnp:class"].element?.text ?? "")
//
//            var metadata: Track.Metadata = .init(ISRC: nil, openInURL: nil, contentType: contentType, stationID: nil)
//            var musicService: MusicService = .unknown
//
//            if xml.lowercased().contains("tunein") {
//                musicService = .tuneIn
//                metadata.stationID = parseStationID(from: xml)
//            }
//
//            return Track(
//                trackID: trackURI ?? "",
//                name: title,
//                artist: artist,
//                album: album,
//                musicService: musicService,
//                metadata: metadata
//            )
//        }
//
//        guard let trackDurationString = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackDuration"].element?.text,
//              let trackURI = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackURI"].element?.text,
//              !trackURI.isEmpty,
//              let trackNumber = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["Track"].element?.text
//        else {
//            return .empty
//        }
//        
//        var name = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["dc:title"].element?.text ?? "Unknown"
//        let album = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["upnp:album"].element?.text
//        let artist = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["dc:creator"].element?.text
//        let albumArtist = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["r:albumArtist"].element?.text
//
//        var playbackPosition = TimeInterval.zero
//        // MARK: Parse out RelTime
//        let pattern = "<RelTime>(.*?)</RelTime>"
//        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
//            let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
//
//            if let match = regex.firstMatch(in: xml, options: [], range: range) {
//                let valueRange = match.range(at: 1)
//                if let valueRange = Range(valueRange, in: xml) {
//                    let timeStamp = String(xml[valueRange])
//                    let components = timeStamp.components(separatedBy: ":")
//                    if components.count == 3,
//                       let hours = Int(components[0]),
//                       let minutes = Int(components[1]),
//                       let seconds = Int(components[2])
//                    {
//                        let totalMilliseconds = ((hours * 60 + minutes) * 60 + seconds) * 1000
//                        playbackPosition = TimeInterval(totalMilliseconds)
//                    }
//                }
//            }
//        }
//
//        var trackDuration = TimeInterval.zero
//        let trackDurationComponents = trackDurationString.components(separatedBy: ":")
//        if trackDurationComponents.count == 3,
//           let hours = Int(trackDurationComponents[0]),
//           let minutes = Int(trackDurationComponents[1]),
//           let seconds = Int(trackDurationComponents[2])
//        {
//            let totalMilliseconds = ((hours * 60 + minutes) * 60 + seconds) * 1000
//            trackDuration = TimeInterval(totalMilliseconds)
//        }
//
//        var musicService: MusicService = trackURI.contains("spotify") ? .spotify : .apple
//        var metadata: Track.Metadata = .init(ISRC: nil, openInURL: nil, contentType: nil, stationID: nil)
//
//        if trackURI.contains("airplay") {
//            musicService = .airplay
//        }
//
//        if trackURI.contains("x-file-cifs") {
//            musicService = .library
//        }
//
//        if xml.lowercased().contains("tunein") {
//            musicService = .tuneIn
//        }
//        
//        if trackURI.contains("%3a3%3") {
//            musicService = .plex
//        }
//
//        if trackURI.contains("librarytrack") {
//            musicService = .apple
//        }
//        
//        if trackURI.contains("x-rincon-stream") {
//            name = "Line In"
//        }
//
//        // TODO: Add hi res icon
////        print(item["res"].element?.attribute(by: "protocolInfo")?.text.removingPercentEncoding)
//        var trackID = ""
//        let tidalPattern = #/track\/(\d{7,9})/#
//        if let trackURIRemovePercent = trackURI.removingPercentEncoding, let result = try? tidalPattern.firstMatch(in: trackURIRemovePercent) {
//            musicService = .tidal
//            trackID = String(result.1)
//        }
//
//        switch musicService {
//        case .apple:
//            let pattern = #/song:(\w*)/#
//            let libraryTrackPattern = #/librarytrack:(.*?)\?/#
//
//            let trackURIRemovePercent = trackURI.removingPercentEncoding
//            if let trackURIRemovePercent, let result = try? pattern.firstMatch(in: trackURIRemovePercent) {
//                trackID = String(result.1)
//            } else if let trackURIRemovePercent, let libraryResult = try? libraryTrackPattern.firstMatch(in: trackURIRemovePercent) {
//                let libraryTrackID = String(libraryResult.1)
//                if let dotRange = libraryTrackID.range(of: ".", options: .backwards), libraryTrackID.filter({ $0 == "." }).count > 1 {
//                    trackID = String(libraryTrackID[..<dotRange.lowerBound])
//                } else {
//                    trackID = libraryTrackID
//                }
//            } else {
//                musicService = .unknown
//            }
//        case .spotify:
//            if let trackInfo = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["res"].element?.text.removingPercentEncoding {
//                let pattern = #/track:(\w*)/#
//                if let result = try? pattern.firstMatch(in: trackInfo) {
//                    trackID = String(result.1)
//                } else {
//                    musicService = .unknown
//                }
//            } else {
//                musicService = .unknown
//            }
//        case .library:
//            trackID = trackURI
//        case .plex:
//            let pattern = "([^:]+:\\d+:\\d+)"
//            if let trackURIRemovePercent = trackURI.removingPercentEncoding, let regex = try? NSRegularExpression(pattern: pattern) {
//                let results = regex.matches(in: trackURIRemovePercent, range: NSRange(trackURIRemovePercent.startIndex..., in: trackURIRemovePercent))
//
//                if let match = results.first {
//                    if let range = Range(match.range, in: trackURIRemovePercent),  let extractedString = String(trackURIRemovePercent[range]).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
//                        trackID = extractedString
//                    }
//                }
//            }
//        case .tuneIn:
//            metadata.stationID = parseStationID(from: xml)
//        case .tidal:
//            break
//        case .airplay, .unknown:
//            break
//        }
//
//        var sonosAlbumArtURL: URL? = nil
//        if let albumArtURI = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["upnp:albumArtURI"].all.first?.element?.text {
//            let ip = preferredIPForTrackAlbumArt ?? IP
//            sonosAlbumArtURL = URL(string: "http://\(ip):1400\(albumArtURI.unescaped)")
//
//            if sonosAlbumArtURL == nil {
//                sonosAlbumArtURL = URL(string: albumArtURI.unescaped)
//                // MARK: Upscale
//                if let sonosAlbumArt = sonosAlbumArtURL?.absoluteString {
//                    let modified = sonosAlbumArt.replacingOccurrences(of: "w=\\d+", with: "w=\(800)", options: .regularExpression)
//                    if let upscaledURL = URL(string: modified) {
//                        sonosAlbumArtURL = upscaledURL
//                    }
//                }
//            }
//        }
//        
//        let position = Int(trackNumber) ?? 1
//
//        return Track(
//            trackID: trackID,
//            name: name,
//            artist: albumArtist ?? (
//                artist ?? ""
//            ),
//            album: album ?? "",
//            musicService: musicService,
//            duration: trackDuration,
//            playbackPosition: playbackPosition,
//            position: position,
//            sonosAlbumArtURL: sonosAlbumArtURL,
//            metadata: metadata
//        )
    }

    func parsePlaybackInfo(xml: String) -> PlaybackStatus {
        guard let value = try? parseValue(xml: xml, named: "CurrentTransportState") else {
            return .unknown
        }
        
        if value == "PLAYING" {
            return .playing
        } else if value == "PAUSED_PLAYBACK" || value == "STOPPED" {
            return .paused
        }

        return .transitioning
    }

    func parseMediaInfo(xml: String) -> PlaybackMediaInfo {
        let queueTotal = (try? parseValue(xml: xml, named: "NrTracks")).flatMap { Int($0) }

        // Early return if we can't parse the URI
        guard let currentURI = try? parseValue(xml: xml, named: "CurrentURI") else {
            return PlaybackMediaInfo(playbackService: .unknown, artwork: nil, title: nil, queueTotal: queueTotal)
        }
        
        // Map URI substrings to their corresponding PlaybackService
        let serviceMapping: [(String, PlaybackService)] = [
            ("htastream", .tv),
            ("radio", .radio),
            ("airplay", .airplay),
            ("queue", .queue),
            ("spotify", .spotifyConnect),
            ("x-sonosapi-stream", .radio),
            ("x-rincon-stream", .lineIn)
        ]
        
        var playbackService = serviceMapping.first { currentURI.contains($0.0) }?.1 ?? .unknown
        
        // MARK: Sonifiy Fix
        if playbackService == .queue {
            if !currentURI.hasSuffix("#0") {
                playbackService = .unknown
            }
        }
        
        var radioTitle: String?
        var albumArtURL: URL?
        if let currentURIMetaData = try? parseValue(xml: xml, named: "CurrentURIMetaData").removingHTMLEntities() {
            radioTitle = try? parseValue(xml: currentURIMetaData, named: "dc:title").removingHTMLEntities()
            let albumArt = try? parseValue(xml: currentURIMetaData, named: "upnp:albumArtURI").removingHTMLEntities()
//            albumArt = albumArt?.replacingOccurrences(of: "logoq.png", with: "logod.jpg")
            albumArtURL = URL(string: albumArt ?? "")?.sonosRadioArtwork()
        }
        
        return PlaybackMediaInfo(playbackService: playbackService, artwork: albumArtURL, title: radioTitle, currentURI: currentURI.removingHTMLEntities(), queueTotal: queueTotal)
    }


    func parseGetCurrentTransportActions(xml: String) -> AvailableActions? {
        guard let parseGetCurrentTransportActions = try? parseValue(xml: xml, named: "Actions") else {
            return nil
        }
        let actions = parseGetCurrentTransportActions.components(separatedBy: ",")
        let availableActions = AvailableActions(actions.compactMap(AvailableActions.init))
        return availableActions
    }

    func parsePlaybackMode(_ xml: String) -> PlayMode? {
        guard let mode = try? parseValue(xml: xml, named: "PlayMode") else {
            return nil
        }
        return PlayMode(mode: mode)
    }

    func parseMute(xml: String) -> Bool? {
        guard let isMuted = try? parseValue(xml: xml, named: "CurrentMute") else {
            return nil
        }
        return isMuted == "1"
    }

    func parseGetCrossfade(xml: String) -> Bool? {
        guard let isCrossfaded = try? parseValue(xml: xml, named: "CrossfadeMode") else {
            return nil
        }
        return isCrossfaded == "1"
    }

    func parseHouseID(xml: String) -> String {
        guard let householdID = try? parseValue(xml: xml, named: "CurrentMuseHouseholdId") else {
            return ""
        }
        return householdID
    }

    func parseSleepTimer(xml: String) -> Date? {
        guard let sleepTimeRemaining = try? parseValue(xml: xml, named: "RemainingSleepTimerDuration") else {
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

    func parseQueue(IP: String, xml: String, preferredIPForTrackAlbumArt: String?) -> [PlayableContent] {
        return QueueParser().parsePlaylistsTracks(IP: IP, xml: xml)
        
//        guard let data = xml.unescaped.data(using: .utf8) else { return [] }
//        let parser = XMLParser(data: data)
//        let delegate = QueueXMLParser(ip: IP, preferredIPForTrackAlbumArt: preferredIPForTrackAlbumArt)
//        parser.delegate = delegate
//        parser.parse()
//        return delegate.tracks
        
//        let xmlParsed = parseXML(xml)
//        guard let resultXML = xmlParsed["s:Envelope"]["s:Body"]["u:BrowseResponse"]["Result"].element?.innerXML else { return []}
//        let resultsParsed = parseXML(resultXML)
//        guard let items = resultsParsed.children.first?.children else { return [] }
//        var tracks: [PlayableContent] = []
//
//        for item in items {
//            guard let trackNumber = Int(item.element?.attribute(by: "id")?.text.components(separatedBy: "/").last ?? "")
//            else {
//                continue
//            }
//
//            let title = item["dc:title"].element?.text ?? "Unknown"
//            let albumArtist = item["r:albumArtist"].element?.text
//            var trackDuration = TimeInterval.zero
//            if let trackDurationString = item["res"].element?.attribute(by: "duration")?.text {
//                let trackDurationComponents = trackDurationString.components(separatedBy: ":")
//                if trackDurationComponents.count == 3,
//                   let hours = Int(trackDurationComponents[0]),
//                   let minutes = Int(trackDurationComponents[1]),
//                   let seconds = Int(trackDurationComponents[2])
//                {
//                    let totalMilliseconds = ((hours * 60 + minutes) * 60 + seconds) * 1000
//                    trackDuration = TimeInterval(totalMilliseconds)
//                }
//            }
//
//            var trackID = title
//            var musicService: MusicService = .unknown
//
//            if let trackURI = item["res"].element?.text.removingPercentEncoding {
//                musicService = trackURI.contains("spotify") ? .spotify : .apple
//                if trackURI.contains("airplay") {
//                    musicService = .airplay
//                }
//
//                if trackURI.contains("x-file-cifs") {
//                    musicService = .library
//                }
//
//                // TODO: Parse with this for HiRes info
////                prin(item["res"].element?.attribute(by: "protocolInfo")?.text.removingPercentEncoding)
//                if trackURI.contains(":3:") {
//                    musicService = .plex
//                }
//
//                let tidalPattern = #/track\/(\d{7,9})/#
//                if let trackURIRemovePercent = trackURI.removingPercentEncoding, let result = try? tidalPattern.firstMatch(in: trackURIRemovePercent) {
//                    musicService = .tidal
//                    trackID = String(result.1)
//                }
//
//                switch musicService {
//                case .apple:
//                    let pattern = #/song:(\w*)/#
//                    let libraryTrackPattern = #/librarytrack:(.*?)\?/#
//
//                    let trackURIRemovePercent = trackURI.removingPercentEncoding
//                    if let trackURIRemovePercent, let result = try? pattern.firstMatch(in: trackURIRemovePercent) {
//                        trackID = String(result.1)
//                    } else if let trackURIRemovePercent, let libraryResult = try? libraryTrackPattern.firstMatch(in: trackURIRemovePercent) {
//                        let libraryTrackID = String(libraryResult.1)
//                        if let dotRange = libraryTrackID.range(of: ".", options: .backwards), libraryTrackID.filter({ $0 == "." }).count > 1 {
//                            trackID = String(libraryTrackID[..<dotRange.lowerBound])
//                        } else {
//                            trackID = libraryTrackID
//                        }
//                    } else {
//                        musicService = .unknown
//                    }
//                case .spotify:
//                    let pattern = #/track:(\w*)/#
//                    if let result = try? pattern.firstMatch(in: trackURI) {
//                        trackID = String(result.1)
//                    } else {
//                        musicService = .unknown
//                    }
//                case .airplay, .unknown:
//                    musicService = .unknown
//                case .library:
//                    trackID = item["res"].element?.text ?? ""
//                case .plex:
//                    let pattern = "([^:]+:\\d+:\\d+)"
//                    if let trackURIRemovePercent = trackURI.removingPercentEncoding, let regex = try? NSRegularExpression(pattern: pattern) {
//                        let results = regex.matches(in: trackURIRemovePercent, range: NSRange(trackURIRemovePercent.startIndex..., in: trackURIRemovePercent))
//                        if let match = results.first {
//                            if let range = Range(match.range, in: trackURIRemovePercent),  let extractedString = String(trackURIRemovePercent[range]).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
//                                trackID = extractedString
//                            }
//                        }
//                    }
//                case .tidal, .tuneIn:
//                    break
//                }
//            }
//
//            let artist = item["dc:creator"].element?.text
//            var sonosAlbumArtURL: URL?
//            if let albumArtURI = item["upnp:albumArtURI"].all.first?.element?.text {
//                let ip = preferredIPForTrackAlbumArt ?? IP
//                sonosAlbumArtURL = URL(string: "http://\(ip):1400\(albumArtURI.unescaped)")
//
//                if sonosAlbumArtURL == nil {
//                    sonosAlbumArtURL = URL(string: albumArtURI.unescaped)
//                    // MARK: Upscale
//                    if let sonosAlbumArt = sonosAlbumArtURL?.absoluteString {
//                        let modified = sonosAlbumArt.replacingOccurrences(of: "w=\\d+", with: "w=\(800)", options: .regularExpression)
//                        if let upscaledURL = URL(string: modified) {
//                            sonosAlbumArtURL = upscaledURL
//                        }
//                    }
//                }
//            }
//
//            var emptyArtist = ""
//            if let albumArtist {
//                emptyArtist = albumArtist
//            } else if let artist {
//                emptyArtist = artist
//            }
//
//            var emptyAlbum = ""
//            if let album = item["upnp:album"].element?.text {
//                emptyAlbum = album
//            }
//
//            var subtitle = ""
//            subtitle = [emptyArtist, emptyAlbum].filter({ !$0.isEmpty }).joined(separator: " • ")
//            
//            let mediaContent = MediaContent(
//                service: musicService,
//                id: trackID,
//                type: trackID.contains(
//                    "i."
//                ) ? .libraryTrack : .track,
//                location: nil
//            )
//            let metadata = PlayableContentMetadata(
//                duration: Duration.milliseconds(
//                    trackDuration
//                ),
//                artist: emptyArtist,
//                album: emptyAlbum,
//                position: trackNumber
//            )
//            let playableContent = PlayableContent(
//                title: title,
//                subtitle: subtitle,
//                thumbnail: sonosAlbumArtURL,
//                artwork: sonosAlbumArtURL,
//                content: mediaContent,
//                metadata: metadata
//            )
//            tracks.append(playableContent)
//        }
//        return tracks
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
    
    func parseValue(xml: String, named: String) throws -> String {
        // Use NSRegularExpression with proper error handling
        let pattern = "<\(named)>(.*?)</\(named)>"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            throw XMLParserSonosError.parsing
        }
        
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        
        guard let match = regex.firstMatch(in: xml, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: xml) else {
            throw XMLParserSonosError.parsing
        }
        
        let value = String(xml[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    func extractValue<T: LosslessStringConvertible>(from xmlData: Data, for tag: String) -> T? {
        let xml = String(decoding: xmlData, as: UTF8.self)
        let pattern = "<\(tag)>(.*?)</\(tag)>"
        guard let range = xml.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let valueString = String(xml[range])
            .replacingOccurrences(of: "<\(tag)>", with: "")
            .replacingOccurrences(of: "</\(tag)>", with: "")
        return T(valueString)
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
        return LibraryParser().parse(IP: IP, xml: xml)
        
//        
//        let xmlParsed = parseXML(xml)
//        guard let resultXML = xmlParsed["s:Envelope"]["s:Body"]["u:BrowseResponse"]["Result"].element?.innerXML else { return []}
//        let resultsParsed = parseXML(resultXML)
//        guard let items = resultsParsed.children.first?.children else { return [] }
//
//        var searchResults: [PlayableContent] = []
//
//        for item in items {
//            print(item)
//            guard let title = item["dc:title"].element?.text,
//                  let trackID = item["res"].element?.text,
//                  let type = item["upnp:class"].element?.text,
//                  let contentType = ContentType(type) else {
//                continue
//            }
//
//
//            var artist = ""
//
//            let album = item["upnp:album"].element?.text
//            let trackAlbumArtist = item["r:albumArtist"].element?.text
//            let creator = item["dc:creator"].element?.text
//            let albumID = item.element?.allAttributes["parentID"]?.text
//
//            var sonosAlbumArtURL: URL?
//            if let albumArtURI = item["upnp:albumArtURI"].all.first?.element?.text {
//                sonosAlbumArtURL = URL(string: "http://\(IP):1400\(albumArtURI.unescaped)")
//            }
//
//            var subtitle = ""
//            switch contentType {
//            case .album:
//                artist = creator ?? ""
//                subtitle = "\(artist)"
//            case .track:
//                artist = (trackAlbumArtist ?? creator) ?? ""
//                if let album {
//                    subtitle = [artist, album].joined(separator: " • ")
//                }
//            default:
//                break
//            }
//
//            let mediaContent = MediaContent(service: .library, id: trackID, type: contentType, location: nil)
//            let metadata = PlayableContentMetadata(artist: artist, album: album, albumID: albumID)
//            let playableContent = PlayableContent(title: title, subtitle: subtitle, thumbnail: sonosAlbumArtURL, artwork: sonosAlbumArtURL, content: mediaContent, metadata: metadata)
//            searchResults.append(playableContent)
//        }
//
//        return searchResults
    }

    func parsePlaylists(IP: String, xml: String) -> [PlayableContent] {
        return PlaylistParser().parsePlaylists(IP: IP, xml: xml)

//        return []
//        
//        let xmlParsed = parseXML(xml)
//        guard let resultXML = xmlParsed["s:Envelope"]["s:Body"]["u:BrowseResponse"]["Result"].element?.innerXML else { return []}
//        let resultsParsed = parseXML(resultXML)
//        guard let items = resultsParsed.children.first?.children else { return [] }
//
//        var searchResults: [PlayableContent] = []
//
//        for item in items {
//            guard let title = item["dc:title"].element?.text,
//                  let trackID = item["res"].element?.text,
//                  let type = item["upnp:class"].element?.text,
//                  let contentType = ContentType(type) else {
//                continue
//            }
//
//
//            var artist = ""
//
//            let album = item["upnp:album"].element?.text
//            let trackAlbumArtist = item["r:albumArtist"].element?.text
//            let creator = item["dc:creator"].element?.text
//            let albumID = item.element?.allAttributes["parentID"]?.text
//            var sonosAlbumArtURL: URL?
//            if let albumArtURI = item["upnp:albumArtURI"].all.first?.element?.text {
//                sonosAlbumArtURL = URL(string: "http://\(IP):1400\(albumArtURI.unescaped)")
//            }
//
//            var subtitle = ""
//            switch contentType {
//            case .album:
//                artist = creator ?? ""
//                subtitle = "\(artist)"
//            case .track:
//                artist = (trackAlbumArtist ?? creator) ?? ""
//                if let album {
//                    subtitle = [artist, album].joined(separator: " • ")
//                }
//            default:
//                break
//            }
//
//            let mediaContent = MediaContent(service: .library, id: trackID, type: contentType, location: nil)
//            let metadata = PlayableContentMetadata(artist: artist, album: album, albumID: albumID)
//            let playableContent = PlayableContent(title: title, subtitle: subtitle, thumbnail: sonosAlbumArtURL, artwork: sonosAlbumArtURL, content: mediaContent, metadata: metadata)
//            searchResults.append(playableContent)
//        }
//
//        return searchResults
    }
    
    func parsePlaylistsTracks(IP: String, xml: String) -> [PlayableContent] {
        PlaylistParser().parsePlaylistsTracks(IP: IP, xml: xml)
    }
    
    
//    func oldParse(IP: String, xml: String) -> [PlayableContent] {
//        let xmlParsed = parseXML(xml)
//        guard let resultXML = xmlParsed["s:Envelope"]["s:Body"]["u:BrowseResponse"]["Result"].element?.innerXML else { return [] }
//        let resultsParsed = XMLHash.parse(resultXML)
//        guard let items = resultsParsed.children.first?.children else { return [] }
//
//        var searchResults: [PlayableContent] = []
//
//        for item in items {
//            guard let title = item["dc:title"].element?.text,
//                  var trackID = item["res"].element?.text,
//                  let type = item["upnp:class"].element?.text,
//                  let contentType = ContentType(type) else {
//                continue
//            }
//
//
//            var artist = ""
//
//            let album = item["upnp:album"].element?.text
//            let trackAlbumArtist = item["r:albumArtist"].element?.text
//            let creator = item["dc:creator"].element?.text
//            let albumID = item.element?.allAttributes["parentID"]?.text
//            var sonosAlbumArtURL: URL?
//            if let albumArtURI = item["upnp:albumArtURI"].all.first?.element?.text {
//                sonosAlbumArtURL = URL(string: "http://\(IP):1400\(albumArtURI.unescaped)")
//            }
//
//            var subtitle = ""
//            switch contentType {
//            case .album:
//                artist = creator ?? ""
//                subtitle = "\(artist)"
//            case .track:
//                artist = (trackAlbumArtist ?? creator) ?? ""
//                if let album {
//                    subtitle = "\(artist) • \(album)"
//                }
//            default:
//                break
//            }
//
//            var musicService = MusicService.unknown
//            if let trackURI = item["res"].element?.text.removingPercentEncoding {
//                musicService = trackURI.contains("spotify") ? .spotify : .apple
//                if trackURI.contains("airplay") {
//                    musicService = .airplay
//                }
//
//                if trackURI.contains("x-file-cifs") {
//                    musicService = .library
//                }
//
//                // TODO: Parse with this for HiRes info
////                print(item["res"].element?.attribute(by: "protocolInfo")?.text.removingPercentEncoding)
//
//                // MarkLook for Client ID
//                if trackURI.contains("x-sonos-http") {
//                    musicService = .plex
//                }
//
//                let tidalPattern = #/track\/(\d{7,9})/#
//                if let trackURIRemovePercent = trackURI.removingPercentEncoding, let result = try? tidalPattern.firstMatch(in: trackURIRemovePercent) {
//                    musicService = .tidal
//                    trackID = String(result.1)
//                }
//
//                switch musicService {
//                case .apple:
//                    let pattern = #/song:(\w*)/#
//                    let libraryTrackPattern = #/librarytrack:(.*?)\?/#
//
//                    let trackURIRemovePercent = trackURI.removingPercentEncoding
//                    if let trackURIRemovePercent, let result = try? pattern.firstMatch(in: trackURIRemovePercent) {
//                        trackID = String(result.1)
//                    } else if let trackURIRemovePercent, let libraryResult = try? libraryTrackPattern.firstMatch(in: trackURIRemovePercent) {
//                        let libraryTrackID = String(libraryResult.1)
//                        if let dotRange = libraryTrackID.range(of: ".", options: .backwards), libraryTrackID.filter({ $0 == "." }).count > 1 {
//                            trackID = String(libraryTrackID[..<dotRange.lowerBound])
//                        } else {
//                            trackID = libraryTrackID
//                        }
//                    } else {
//                        musicService = .unknown
//                    }
//                case .spotify:
//                    let pattern = #/track:(\w*)/#
//                    if let result = try? pattern.firstMatch(in: trackURI) {
//                        trackID = String(result.1)
//                    } else {
//                        musicService = .unknown
//                    }
//                case .airplay, .unknown, .tuneIn:
//                    musicService = .unknown
//                case .library:
//                    trackID = item["res"].element?.text ?? ""
//                case .plex:
//                    // MARK: Verify
//                    trackID = item["res"].element?.text ?? ""
//                case .tidal:
//                    break
//                }
//            }
//
//            var trackDuration = Duration.zero
//            if let trackDurationString = item["res"].element?.attribute(by: "duration")?.text {
//                let trackDurationComponents = trackDurationString.components(separatedBy: ":")
//                if trackDurationComponents.count == 3,
//                   let hours = Int(trackDurationComponents[0]),
//                   let minutes = Int(trackDurationComponents[1]),
//                   let seconds = Int(trackDurationComponents[2])
//                {
//                    let totalMilliseconds = ((hours * 60 + minutes) * 60 + seconds) * 1000
//                    trackDuration = Duration.milliseconds(totalMilliseconds)
//                }
//            }
//
//            let mediaContent = MediaContent(service: musicService, id: trackID, type: contentType, location: nil)
//            let metadata = PlayableContentMetadata(duration: trackDuration, artist: artist, album: album, albumID: albumID)
//            let playableContent = PlayableContent(title: title, subtitle: subtitle, thumbnail: sonosAlbumArtURL, artwork: sonosAlbumArtURL, content: mediaContent, metadata: metadata)
//            searchResults.append(playableContent)
//        }
//
//        return searchResults
//    }


//    func parsePlaylistsTracks(IP: String, xml: String) -> [PlayableContent] {
//        let xmlParsed = parseXML(xml)
//        guard let resultXML = xmlParsed["s:Envelope"]["s:Body"]["u:BrowseResponse"]["Result"].element?.innerXML else { return [] }
//        let resultsParsed = XMLHash.parse(resultXML)
//        guard let items = resultsParsed.children.first?.children else { return [] }
//
//        var searchResults: [PlayableContent] = []
//
//        for item in items {
//            guard let title = item["dc:title"].element?.text,
//                  var trackID = item["res"].element?.text,
//                  let type = item["upnp:class"].element?.text,
//                  let contentType = ContentType(type) else {
//                continue
//            }
//
//
//            var artist = ""
//
//            let album = item["upnp:album"].element?.text
//            let trackAlbumArtist = item["r:albumArtist"].element?.text
//            let creator = item["dc:creator"].element?.text
//            let albumID = item.element?.allAttributes["parentID"]?.text
//            var sonosAlbumArtURL: URL?
//            if let albumArtURI = item["upnp:albumArtURI"].all.first?.element?.text {
//                sonosAlbumArtURL = URL(string: "http://\(IP):1400\(albumArtURI.unescaped)")
//            }
//
//            var subtitle = ""
//            switch contentType {
//            case .album:
//                artist = creator ?? ""
//                subtitle = "\(artist)"
//            case .track:
//                artist = (trackAlbumArtist ?? creator) ?? ""
//                if let album {
//                    subtitle = "\(artist) • \(album)"
//                }
//            default:
//                break
//            }
//
//            var musicService = MusicService.unknown
//            if let trackURI = item["res"].element?.text.removingPercentEncoding {
//                musicService = trackURI.contains("spotify") ? .spotify : .apple
//                if trackURI.contains("airplay") {
//                    musicService = .airplay
//                }
//
//                if trackURI.contains("x-file-cifs") {
//                    musicService = .library
//                }
//
//                // TODO: Parse with this for HiRes info
////                print(item["res"].element?.attribute(by: "protocolInfo")?.text.removingPercentEncoding)
//
//                // MarkLook for Client ID
//                if trackURI.contains("x-sonos-http") {
//                    musicService = .plex
//                }
//
//                let tidalPattern = #/track\/(\d{7,9})/#
//                if let trackURIRemovePercent = trackURI.removingPercentEncoding, let result = try? tidalPattern.firstMatch(in: trackURIRemovePercent) {
//                    musicService = .tidal
//                    trackID = String(result.1)
//                }
//
//                switch musicService {
//                case .apple:
//                    let pattern = #/song:(\w*)/#
//                    let libraryTrackPattern = #/librarytrack:(.*?)\?/#
//
//                    let trackURIRemovePercent = trackURI.removingPercentEncoding
//                    if let trackURIRemovePercent, let result = try? pattern.firstMatch(in: trackURIRemovePercent) {
//                        trackID = String(result.1)
//                    } else if let trackURIRemovePercent, let libraryResult = try? libraryTrackPattern.firstMatch(in: trackURIRemovePercent) {
//                        let libraryTrackID = String(libraryResult.1)
//                        if let dotRange = libraryTrackID.range(of: ".", options: .backwards), libraryTrackID.filter({ $0 == "." }).count > 1 {
//                            trackID = String(libraryTrackID[..<dotRange.lowerBound])
//                        } else {
//                            trackID = libraryTrackID
//                        }
//                    } else {
//                        musicService = .unknown
//                    }
//                case .spotify:
//                    let pattern = #/track:(\w*)/#
//                    if let result = try? pattern.firstMatch(in: trackURI) {
//                        trackID = String(result.1)
//                    } else {
//                        musicService = .unknown
//                    }
//                case .airplay, .unknown, .tuneIn:
//                    musicService = .unknown
//                case .library:
//                    trackID = item["res"].element?.text ?? ""
//                case .plex:
//                    // MARK: Verify
//                    trackID = item["res"].element?.text ?? ""
//                case .tidal:
//                    break
//                }
//            }
//
//            var trackDuration = Duration.zero
//            if let trackDurationString = item["res"].element?.attribute(by: "duration")?.text {
//                let trackDurationComponents = trackDurationString.components(separatedBy: ":")
//                if trackDurationComponents.count == 3,
//                   let hours = Int(trackDurationComponents[0]),
//                   let minutes = Int(trackDurationComponents[1]),
//                   let seconds = Int(trackDurationComponents[2])
//                {
//                    let totalMilliseconds = ((hours * 60 + minutes) * 60 + seconds) * 1000
//                    trackDuration = Duration.milliseconds(totalMilliseconds)
//                }
//            }
//
//            let mediaContent = MediaContent(service: musicService, id: trackID, type: contentType, location: nil)
//            let metadata = PlayableContentMetadata(duration: trackDuration, artist: artist, album: album, albumID: albumID)
//            let playableContent = PlayableContent(title: title, subtitle: subtitle, thumbnail: sonosAlbumArtURL, artwork: sonosAlbumArtURL, content: mediaContent, metadata: metadata)
//            searchResults.append(playableContent)
//        }
//
//        return searchResults
//    }

//    func parseFavorites(IP: String, xml: String) -> [PlayableContent] {
//        let xmlParsed = parseXML(xml)
//        guard let resultXML = xmlParsed["s:Envelope"]["s:Body"]["u:BrowseResponse"]["Result"].element?.innerXML else { return []}
//        let resultsParsed = XMLHash.parse(resultXML)
//        guard let items = resultsParsed.children.first?.children else { return [] }
//
//        var searchResults: [PlayableContent] = []
//
//        for item in items {
//            guard let title = item["dc:title"].element?.text,
//                  let trackID = item["res"].element?.text.encodeProgramURI,
//                  var uriMetadata = item["r:resMD"].element?.text.unescaped else {
//                continue
//            }
//            let innerXML = XMLHash.parse(uriMetadata)
//            let type = innerXML["DIDL-Lite"]["item"]["upnp:class"].element?.text ?? ""
//            let contentType = ContentType(type) ?? .favorite
//            
//            var sonosAlbumArtURL: URL?
//            if let albumArtURI = item["upnp:albumArtURI"].all.first?.element?.text {
//                sonosAlbumArtURL = URL(string: albumArtURI)
//            }
//
//            var subtitle: String = ""
//            if let description = item["r:description"].element?.text {
//                subtitle = description
//            }
//            
//            uriMetadata = sanitizeDCTitle(uriMetadata)
//
//            let isRadioStation = uriMetadata.contains("audioBroadcast") || uriMetadata.contains("radio")
//            let mediaContent = MediaContent(service: .unknown, id: trackID, type: contentType, location: nil)
//            let metadata = PlayableContentMetadata(URIMetadata: uriMetadata.escaped, radioStation: isRadioStation)
//            let playableContent = PlayableContent(title: title, subtitle: subtitle, thumbnail: sonosAlbumArtURL, artwork: sonosAlbumArtURL, content: mediaContent, metadata: metadata)
//            searchResults.append(playableContent)
//        }
//
//        
//        let parser = FavoritesParser()
//        let contents = parser.parse(xml: xml)
//        return contents
//
//        return contents
//    }
    
    func parseFavorites(IP: String, xml: String) -> [PlayableContent] {
        let parser = FavoritesParser()
        let contents = parser.parse(xml: xml)
        return contents
    }

    func parseContentType(from xmlString: String) -> ContentType? {
        let pattern = "<upnp:class>(.*?)</upnp:class>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let nsRange = NSRange(xmlString.startIndex..<xmlString.endIndex, in: xmlString)
        
        if let match = regex?.firstMatch(in: xmlString, options: [], range: nsRange),
           let range = Range(match.range(at: 1), in: xmlString) {
            let classType = String(xmlString[range])
            return ContentType(classType)
        }
        
        return nil
    }

    func parseGetUpdateId(IP: String, xml: String) -> String {
        guard let updateID = try? parseValue(xml: xml, named: "UpdateID") else {
            return "0"
        }
        return updateID
    }

    // MARK: Alarm Clock
    func parseAlarmClockList(from xml: String) -> [Alarm] {
        let parser = AlarmListParser()
        let newAlarms = parser.parseAlarms(from: xml)
        return newAlarms
    }
    
//    func parseAlarmClockList(from xml: String) -> [Alarm] {
//        
//        //        guard let xmlData = xml.unescaped.data(using: .utf8) else { return [] }
//        
//     
//        let xmlParsed = parseXML(xml)
//        guard let resultXML = xmlParsed["s:Envelope"]["s:Body"]["u:ListAlarmsResponse"]["CurrentAlarmList"].element?.innerXML else { return [] }
//        let resultsParsed = XMLHash.parse(resultXML)
//        guard let items = resultsParsed.children.first?.children else { return [] }
//
//        var alarms: [Alarm] = []
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "hh:mm:ss"
//
//        for item in items {
//            guard let id = item.element?.attribute(by: "ID")?.text,
//                  let roomUUID = item.element?.attribute(by: "RoomUUID")?.text,
//                  let startTime = item.element?.attribute(by: "StartTime")?.text,
//                  let duration = item.element?.attribute(by: "Duration")?.text,
//                  let recurrence = item.element?.attribute(by: "Recurrence")?.text,
//                  let enabled = item.element?.attribute(by: "Enabled")?.text,
//                  let programURI = item.element?.attribute(by: "ProgramURI")?.text,
//                  let programMetaData = item.element?.attribute(by: "ProgramMetaData")?.text,
//                  let includeLinkedZones = item.element?.attribute(by: "IncludeLinkedZones")?.text,
//                  let volume = item.element?.attribute(by: "Volume")?.text,
//                  let playMode = item.element?.attribute(by: "PlayMode")?.text
//            else {
//                continue
//            }
//
//            var day = Calendar.current.startOfDay(for: .now)
//            let startTimeComponents = startTime.components(separatedBy: ":")
//            if startTimeComponents.count == 3, let hours = Int(startTimeComponents[0]), let minutes = Int(startTimeComponents[1]), let seconds = Int(startTimeComponents[2]) {
//                let totalSeconds = (hours * 60 * 60) + (minutes * 60) + seconds
//                day.addTimeInterval(Double(totalSeconds))
//            }
//
//            var alarmDuration = Duration.zero
//            let trackDurationComponents = duration.components(separatedBy: ":")
//            if trackDurationComponents.count == 3, let hours = Int(trackDurationComponents[0]), let minutes = Int(trackDurationComponents[1]), let seconds = Int(trackDurationComponents[2]) {
//                let totalSeconds = (hours * 60 * 60) + (minutes * 60) + seconds
//                alarmDuration = Duration.seconds(totalSeconds)
//            }
//
//            let alarm = Alarm(
//                id: id,
//                roomID: roomUUID,
//                enabled: enabled == "1",
//                startTime: day,
//                duration: alarmDuration,
//                schedule: Frequency(mode: recurrence),
//                programURI: programURI,
//                programMetaData: programMetaData,
//                volume: Double(volume) ?? 0,
//                includeLinkedZones: includeLinkedZones == "1",
//                playMode: PlayMode(mode: playMode) ?? .normal,
//                scheduleRaw: recurrence,
//                shuffle: playMode == "SHUFFLE"
//            )
//            alarms.append(alarm)
//        }
//        
//        let parser = AlarmListParser()
//        let newAlarms = parser.parseAlarms(from: xml)
//        
//        return newAlarms
//    }


//    func parseAlarmClockInfo(uri: String, metadataXML: String?) -> PlayableContent? {
//        guard var metadataXML, !metadataXML.isEmpty else {
//            return PlayableContent(
//                title: "Sonos Chime",
//                subtitle: "",
//                thumbnail: nil,
//                artwork: nil,
//                content: MediaContent(
//                    service: .unknown,
//                    id: uri,
//                    type: .track,
//                    location: nil
//                ),
//                metadata: nil
//            )
//        }
//        if metadataXML.contains("&gt") {
//            metadataXML = metadataXML.unescaped
//        }
//        let xmlParsed = parseXML(metadataXML)
//
//        guard let name = xmlParsed["DIDL-Lite"]["item"]["dc:title"].element?.text else {
//            return nil
//        }
//        
//        let type = xmlParsed["DIDL-Lite"]["item"]["upnp:class"].element?.text ?? ""
//        let contentType = ContentType(type)
//
//
//        return PlayableContent(
//            title: name,
//            subtitle: "",
//            thumbnail: nil,
//            artwork: nil,
//            content: MediaContent(
//                service: .unknown,
//                id: uri,
//                type: contentType ?? .album,
//                location: nil
//            ),
//            metadata: nil
//        )
//    }
    
    func parseAlarmClockInfo(uri: String, metadataXML: String?) -> PlayableContent? {
        // Handle default Sonos Chime case
        guard var metadataXML = metadataXML, !metadataXML.isEmpty else {
            return PlayableContent(
                title: "Sonos Chime",
                subtitle: "",
                thumbnail: nil,
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
        guard let data = metadataXML.data(using: .utf8) else { return nil }
        let parser = XMLParser(data: data)
        let delegate = AlarmContentParser()
        parser.delegate = delegate
        parser.parse()
        
        // Get parsed content
        guard let contentInfo = delegate.contentInfo else { return nil }
        let contentType = ContentType(contentInfo.type)
        
        return PlayableContent(
            title: contentInfo.name,
            subtitle: "",
            thumbnail: nil,
            artwork: nil,
            content: MediaContent(
                service: .unknown,
                id: uri,
                type: contentType ?? .radio,
                location: nil
            ),
            metadata: nil
        )
    }

    func parseRadioTrackInfo(information: String) -> (String, String, String) {
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

    func parseStationID(from input: String) -> String? {
        // Define the pattern for the station ID (adjust the pattern as needed)
        let pattern = #"stationId=(\w+)"#

        // Create a regular expression object
        let regex = try? NSRegularExpression(pattern: pattern, options: [])

        // Search for matches
        if let match = regex?.firstMatch(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count)) {
            if let range = Range(match.range(at: 1), in: input) {
                // Extract the station ID
                return String(input[range])
            }
        }
        return nil
    }

    // Add this new method
    private func sanitizeDCTitle(_ xml: String) -> String {
        let pattern = "<dc:title>(.*?)</dc:title>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        
        guard let match = regex?.firstMatch(in: xml, options: [], range: range),
              let titleRange = Range(match.range(at: 1), in: xml) else {
            return xml
        }
        
        var sanitizedXML = xml
        let title = String(xml[titleRange])
        let sanitizedTitle = title.replacingOccurrences(of: "&amp;", with: "")
            .replacingOccurrences(of: "&", with: "")
        
        sanitizedXML = sanitizedXML.replacingOccurrences(of: title, with: sanitizedTitle, options: [], range: titleRange)
        
        return sanitizedXML
    }
}
