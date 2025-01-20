import Foundation

final class AVTransportParser {
    // Function to parse the full XML response
    static func parse(xmlString: String) -> SonosAVTransportEvent? {
        // First extract LastChange content using index access instead of safe
        let components = xmlString.components(separatedBy: "<LastChange>")
        guard components.count > 1,
              let lastChangeContent = components[1].components(separatedBy: "</LastChange>").first,
              let unescapedLastChange = lastChangeContent.removingHTMLEntities() else {
            return nil
        }
        
        // Extract transport state
        let transportState = extractValue(from: unescapedLastChange, forTag: "TransportState")
        let currentPlayMode = extractValue(from: unescapedLastChange, forTag: "CurrentPlayMode")
        let numberOfTracks = Int(extractValue(from: unescapedLastChange, forTag: "NumberOfTracks") ?? "0") ?? 0
        let currentTrack = Int(extractValue(from: unescapedLastChange, forTag: "CurrentTrack") ?? "0") ?? 0
        let currentTrackDuration = extractValue(from: unescapedLastChange, forTag: "CurrentTrackDuration")
        
        // Extract and parse track metadata
        let currentTrackMetaDataRaw = extractValue(from: unescapedLastChange, forTag: "CurrentTrackMetaData")
        let nextTrackMetaDataRaw = extractValue(from: unescapedLastChange, forTag: "r:NextTrackMetaData")
    
        let currentTrackURI = extractValue(from: unescapedLastChange, forTag: "CurrentTrackURI")
        let currentTrackMetaData = parseTrackMetaData(currentTrackMetaDataRaw ?? "")
        
        let nextTrackURI = extractValue(from: unescapedLastChange, forTag: "NextTrackURI")
        let nextTrackMetaData = parseTrackMetaData(nextTrackMetaDataRaw ?? "")
        
        let avTransportURI = extractValue(from: unescapedLastChange, forTag: "AVTransportURI")
        let avTransportURIMetaDataRaw = extractValue(from: unescapedLastChange, forTag: "r:AVTransportTrackMetaData")
        let avTransportURIMetaData = parseTrackMetaData(avTransportURIMetaDataRaw ?? "")
        
        let currentTransportActions = extractValue(from: unescapedLastChange, forTag: "CurrentTransportActions")
        let currentCrossfadeMode = extractValue(from: unescapedLastChange, forTag: "CurrentCrossfadeMode").flatMap { $0 == "1" }
        let isAlarmRunning = extractValue(from: unescapedLastChange, forTag: "AlarmRunning").flatMap { $0 == "1" } ?? false
    
        let (musicServiceType, trackID) = MusicServiceParser().parse(xml: unescapedLastChange, trackURI: currentTrackURI ?? "")

        return SonosAVTransportEvent(
            isAlarmRunning: isAlarmRunning,
            transportState: transportState,
            currentPlayMode: currentPlayMode,
            queueTotal: numberOfTracks,
            currentTrackPosition: currentTrack,
            currentTrackDuration: currentTrackDuration,
            currentTrackURI: currentTrackURI ?? "",
            currentTrackMetadata: currentTrackMetaData,
            musicService: musicServiceType,
            trackID: trackID,
            nextTrackURI: nextTrackURI,
            nextTrackMetadata: nextTrackMetaData,
            avTransportURI: avTransportURI,
            avTransportURIMetaData: avTransportURIMetaData,
            currentTransportActions: currentTransportActions,
            currentCrossfadeMode: currentCrossfadeMode
        )
    }
    
    // Helper function to extract values from XML-like strings
    private static func extractValue(from text: String, forTag tag: String) -> String? {
        let pattern = "\(tag) val=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        
        guard let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        
        return String(text[range])
    }
    
    // Helper function to parse track metadata
    private static func parseTrackMetaData(_ metadataString: String) -> SonosTrackMetadata? {
        guard let unescaped = metadataString.removingHTMLEntities() else { return nil }
        // Extract values using simple pattern matching
        let title = extractValue(between: "<dc:title>", and: "</dc:title>", from: unescaped) ?? ""
        let creator = extractValue(between: "<dc:creator>", and: "</dc:creator>", from: unescaped) ?? ""
        let album = extractValue(between: "<upnp:album>", and: "</upnp:album>", from: unescaped) ?? ""
        let albumArtURI = extractValue(between: "<upnp:albumArtURI>", and: "</upnp:albumArtURI>", from: unescaped) ?? ""
        let streamInfoString = extractValue(between: "<r:streamInfo>", and: "</r:streamInfo>", from: unescaped) ?? ""

        return SonosTrackMetadata(
            title: title.unescaped.trimmingCharacters(in: .whitespacesAndNewlines),
            creator: creator.unescaped,
            album: album.unescaped,
            albumArtURI: albumArtURI,
            streamInfo: SonosAudioStreamInfo.parse(from: streamInfoString)
        )
    }
    
    // Helper function to extract content between two strings
    private static func extractValue(between startTag: String, and endTag: String, from text: String) -> String? {
        guard let range = text.range(of: startTag)?.upperBound,
              let endRange = text[range...].range(of: endTag)?.lowerBound else {
            return nil
        }
        return String(text[range..<endRange])
    }
}

// Extension to handle HTML entities in the XML
extension String {
    func removingHTMLEntities() -> String? {
        guard let data = self.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        guard let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return nil
        }
        
        return attributedString.string
    }
}


//// Keep String and Array extensions
//
//// End of file
//
//// String extension to handle HTML entities
//extension String {
//    func removingHTMLEntities() -> String {
//        var result = self
//        result = result.replacingOccurrences(of: "&quot;", with: "\"")
//        result = result.replacingOccurrences(of: "&amp;", with: "&")
//        result = result.replacingOccurrences(of: "&lt;", with: "<")
//        result = result.replacingOccurrences(of: "&gt;", with: ">")
//        result = result.replacingOccurrences(of: "/&gt;", with: ">")
//        result = result.replacingOccurrences(of: "/&lt;", with: "<")
//        return result
//    }
//}

//
//func parsePositionInfo(xml: String, IP: String, preferredIPForTrackAlbumArt: String?) -> Track? {
//    // Check for Radio
//    if let radioText = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["r:streamContent"].element?.text, !radioText.isEmpty {
//        let (title, album, artist) = parseRadioTrackInfo(information: radioText)
//        let trackURI = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackURI"].element?.text
//        let contentType = ContentType(xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["upnp:class"].element?.text ?? "")
//
//        var metadata: Track.Metadata = .init(ISRC: nil, openInURL: nil, contentType: contentType, stationID: nil)
//        var musicService: MusicService = .unknown
//
//        if xml.lowercased().contains("tunein") {
//            musicService = .tuneIn
//            metadata.stationID = parseStationID(from: xml)
//        }
//
//        return Track(
//            trackID: trackURI ?? "",
//            name: title,
//            artist: artist,
//            album: album,
//            musicService: musicService,
//            metadata: metadata
//        )
//    }
//
//    guard let trackDurationString = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackDuration"].element?.text,
//          let trackURI = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackURI"].element?.text,
//          !trackURI.isEmpty,
//          var trackNumber = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["Track"].element?.text
//    else {
//        return .empty
//    }
//
//
//    var sonosAlbumArtURL: URL? = nil
//    if let albumArtURI = xmlParsed["s:Envelope"]["s:Body"]["u:GetPositionInfoResponse"]["TrackMetaData"]["DIDL-Lite"]["item"]["upnp:albumArtURI"].all.first?.element?.text {
//        let ip = preferredIPForTrackAlbumArt ?? IP
//        sonosAlbumArtURL = URL(string: "http://\(ip):1400\(albumArtURI.unescaped)")
//
//        if sonosAlbumArtURL == nil {
//            sonosAlbumArtURL = URL(string: albumArtURI.unescaped)
//            // MARK: Upscale
//            if let sonosAlbumArt = sonosAlbumArtURL?.absoluteString {
//                let modified = sonosAlbumArt.replacingOccurrences(of: "w=\\d+", with: "w=\(800)", options: .regularExpression)
//                if let upscaledURL = URL(string: modified) {
//                    sonosAlbumArtURL = upscaledURL
//                }
//            }
//        }
//    }
//
//    let position = Int(trackNumber) ?? 1
//
//    return Track(
//        trackID: trackID,
//        name: name,
//        artist: albumArtist ?? (
//            artist ?? ""
//        ),
//        album: album ?? "",
//        musicService: musicService,
//        duration: trackDuration,
//        playbackPosition: playbackPosition,
//        position: position,
//        sonosAlbumArtURL: sonosAlbumArtURL,
//        metadata: metadata
//    )
//}
