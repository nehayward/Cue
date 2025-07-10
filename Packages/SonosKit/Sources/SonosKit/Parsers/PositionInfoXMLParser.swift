import Foundation

final class SonosTrackParser {
    
    static func parse(xmlString: String, ip: String, preferredIP: String?) -> Track? {
        guard let bodyContent = extractValue(between: "<s:Body>", and: "</s:Body>", from: xmlString) else {
            return nil
        }
        
        let position = Int(extractValue(between: "<Track>", and: "</Track>", from: bodyContent) ?? "1") ?? 1
        let trackDuration = extractValue(between: "<TrackDuration>", and: "</TrackDuration>", from: bodyContent)
        let trackURI = extractValue(between: "<TrackURI>", and: "</TrackURI>", from: bodyContent) ?? ""
        
        if let track = checkForTV(uri: trackURI) {
            return track
        }
        
        if let track = checkForRadio(body: bodyContent, trackURI: trackURI) {
            return track
        }
        
        guard !trackURI.isEmpty else {
            return .empty
        }
        
        // Extract metadata section
        if let metadataContent = extractValue(between: "<TrackMetaData>", and: "</TrackMetaData>", from: bodyContent.unescaped),
           let itemContent = extractValue(between: "<item", and: "</item>", from: metadataContent) {
            var metadata: Track.Metadata = .init(ISRC: nil, openInURL: nil, contentType: nil, stationID: nil)

            // Parse track metadata
            var title = extractValue(between: "<dc:title>", and: "</dc:title>", from: itemContent) ?? "Unknown"
            let creator = extractValue(between: "<dc:creator>", and: "</dc:creator>", from: itemContent)
            let album = extractValue(between: "<upnp:album>", and: "</upnp:album>", from: itemContent)
            let albumArtist = extractValue(between: "<r:albumArtist>", and: "</r:albumArtist>", from: itemContent)
            let albumArtURI = extractValue(between: "<upnp:albumArtURI>", and: "</upnp:albumArtURI>", from: itemContent) ?? ""
            
            let duration = parseTime(bodyContent.unescaped, for: "TrackDuration")
            let playbackPosition = parseTime(bodyContent.unescaped)
            var (musicServiceType, trackID) = MusicServiceParser().parse(xml: bodyContent.unescaped, trackURI: trackURI)
            
            // If trackID is empty and it's a Sonos service, extract from <res> tag
            if trackID.isEmpty, musicServiceType == .spotify {
                if let resContent = extractValue(between: "<res", and: "</res>", from: itemContent),
                   let resStart = resContent.range(of: ">")?.upperBound {
                    let resURI = String(resContent[resStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    // Extract track ID from res URI like "x-sonos-spotify:spotify:track:0vOkmmJEtjuFZDzrQSFzEE"
                    if let trackMatch = resURI.range(of: "track:") {
                        let afterTrack = resURI[trackMatch.upperBound...]
                        let extractedID = String(afterTrack.prefix(while: { $0.isLetter || $0.isNumber }))
                        if !extractedID.isEmpty {
                            trackID = extractedID
                        }
                    }
                }
            }
            
            let ip = preferredIP ?? ip
            var sonosAlbumArtURL: URL?
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
            
            if trackURI.contains("x-rincon-stream") {
                title = "Line In"
            }
            
            if trackURI.contains("sonos"), musicServiceType != .spotify {
                // Decode HTML entities
                let htmlDecoded = albumArtURI.replacingOccurrences(of: "&amp;", with: "&")

                // Extract mark= value
                if let markRange = htmlDecoded.range(of: "mark=") {
                    let markEncoded = htmlDecoded[markRange.upperBound...]
                        .components(separatedBy: "&")
                        .first ?? ""
                    
                    if let decodedMark = markEncoded.removingPercentEncoding {
                        print(decodedMark)  // ✅ Final URL
                        sonosAlbumArtURL = URL(string: decodedMark)
                    }
                }
            }
            
            if title.contains("bump_sonic_pre.mp3") {
                title = ""
            }

            return Track(
                trackID: trackID,
                name: title,
                artist: albumArtist ?? (
                    creator ?? ""
                ),
                album: album ?? "",
                musicService: musicServiceType,
                duration: duration,
                playbackPosition: playbackPosition,
                position: position,
                sonosAlbumArtURL: sonosAlbumArtURL,
                metadata: metadata
            )
        }
        
        let (musicServiceType, trackID) = MusicServiceParser().parse(xml: bodyContent.unescaped, trackURI: trackURI)
        
        return Track(
            trackID: trackID,
            musicService: musicServiceType,
            duration: .zero,
            playbackPosition: .zero,
            position: position,
            metadata: nil
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
    
    // Helper function to extract content between two strings
    private static func extractValue(between startTag: String, and endTag: String, from text: String) -> String? {
        guard let range = text.range(of: startTag)?.upperBound,
              let endRange = text[range...].range(of: endTag)?.lowerBound else {
            return nil
        }
        return String(text[range..<endRange])
    }
    
    // Helper function to parse track metadata
    private static func parseTrackMetaData(_ metadataString: String) -> Track.Metadata? {
        let unescaped = metadataString.removingHTMLEntities()
        print(unescaped)
        // Extract values using simple pattern matching
        let title = extractValue(between: "<dc:title>", and: "</dc:title>", from: unescaped) ?? ""
        let creator = extractValue(between: "<dc:creator>", and: "</dc:creator>", from: unescaped) ?? ""
        let album = extractValue(between: "<upnp:album>", and: "</upnp:album>", from: unescaped) ?? ""
        let albumArtURI = extractValue(between: "<upnp:albumArtURI>", and: "</upnp:albumArtURI>", from: unescaped) ?? ""
        let streamInfoString = extractValue(between: "<r:streamInfo>", and: "</r:streamInfo>", from: unescaped) ?? ""

//        return Track.Metadata(
//            title: title.unescaped.trimmingCharacters(in: .whitespacesAndNewlines),
//            creator: creator.unescaped,
//            album: album.unescaped,
//            albumArtURI: albumArtURI
//        )
        return nil
    }
    
    
    private static func checkForTV(uri: String) -> Track? {
        uri.contains("htastream") ? Track(trackID: "") : nil
    }
    
    private static func checkForRadio(body: String, trackURI: String) -> Track? {
        
        let streamContent = extractValue(between: "<r:streamContent>", and: "</r:streamContent>", from: body)
        
        guard let streamContent, !streamContent.isEmpty, streamContent != "ZPSTR_CONNECTING" else { return nil }
        let (title, album, artist) = XMLParserSonos().parseRadioTrackInfo(information: streamContent)
        
        let contentType = ContentType(extractValue(between: "<upnp:class>", and: "</upnp:class>", from: body) ?? "")

        var metadata: Track.Metadata = .init(ISRC: nil, openInURL: nil, contentType: contentType, stationID: nil)
        var musicService: MusicService = .unknown

        if body.lowercased().contains("tunein") {
            musicService = .tuneIn
            metadata.stationID =  XMLParserSonos().parseStationID(from: body)
        }

        return Track(
            trackID: trackURI,
            name: title,
            artist: artist,
            album: album,
            musicService: musicService,
            metadata: metadata
        )
    }
    
    private static func parseTime(_ xml: String, for time: String = "RelTime") -> TimeInterval {
        // MARK: Parse out RelTime
        let pattern = "<\(time)>(.*?)</\(time)>"
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
                        return TimeInterval(totalMilliseconds)
                    }
                }
            }
        }
        return .zero
    }
}
