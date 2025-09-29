import Foundation

// Your imports remain the same
final class SonosTrackParser {
    // Function to parse the full XML response
    static func parse(xmlString: String, ip: String, preferredIP: String?) -> SonosTrack? {
        // First extract the body content
        guard let bodyContent = extractValue(between: "<s:Body>", and: "</s:Body>", from: xmlString) else {
            return nil
        }
        
        let position = Int(extractValue(between: "<Track>", and: "</Track>", from: bodyContent) ?? "0") ?? 0
        let trackDuration = extractValue(between: "<TrackDuration>", and: "</TrackDuration>", from: bodyContent)
        var trackURI = extractValue(between: "<TrackURI>", and: "</TrackURI>", from: bodyContent) ?? ""
        
        // Extract metadata section
        if let metadataContent = extractValue(between: "<TrackMetaData>", and: "</TrackMetaData>", from: bodyContent.unescaped),
           let itemContent = extractValue(between: "<item", and: "</item>", from: metadataContent) {
            
            // Parse track metadata
            var title = extractValue(between: "<dc:title>", and: "</dc:title>", from: itemContent) ?? ""
            let creator = extractValue(between: "<dc:creator>", and: "</dc:creator>", from: itemContent) ?? ""
            let album = extractValue(between: "<upnp:album>", and: "</upnp:album>", from: itemContent) ?? ""
            let albumArtURI = extractValue(between: "<upnp:albumArtURI>", and: "</upnp:albumArtURI>", from: itemContent) ?? ""
            let streamContent = extractValue(between: "<r:streamContent>", and: "</r:streamContent>", from: itemContent) ?? ""
            let upnpClass = extractValue(between: "<upnp:class>", and: "</upnp:class>", from: itemContent) ?? ""
            
            // Create track metadata
            let metadata = SonosTrackMetadata(
                title: title.unescaped.trimmingCharacters(in: .whitespacesAndNewlines),
                creator: creator.unescaped,
                album: album.unescaped,
                albumArtURI: albumArtURI,
                streamInfo: streamContent.isEmpty ? nil : SonosAudioStreamInfo.parse(from: streamContent)
            )
            var (musicServiceType, trackID) = MusicServiceParser().parse(xml: bodyContent.unescaped, trackURI: trackURI)

            let ip = preferredIP ?? ip
            var sonosAlbumArtURL: URL?
            if !albumArtURI.unescaped.isEmpty {
                sonosAlbumArtURL = URL(string: "http://\(ip):1400\(albumArtURI.unescaped)")
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
            
            return SonosTrack(
                trackID: trackID,
                trackURI: trackURI,
                name: title.unescaped,
                artist: creator.unescaped,
                album: album.unescaped,
                musicService: musicServiceType,
                duration: .zero,
                playbackPosition: .zero,
                position: position,
                sonosAlbumArtURL: sonosAlbumArtURL,
                metadata: nil,
                albumArtURI: albumArtURI
            )
        }
        
        let (musicServiceType, trackID) = MusicServiceParser().parse(xml: bodyContent.unescaped, trackURI: trackURI)
        return SonosTrack(
            trackID: trackID,
            trackURI: trackURI,
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
        
        let content = String(text[range..<endRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }
    
    // Helper function to parse track metadata
    private static func parseTrackMetaData(_ metadataString: String) -> SonosTrackMetadata? {
        guard let unescaped = metadataString.removingHTMLEntities() else { return nil }
        print(unescaped)
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
}

// String extension to handle HTML entities
extension String {
    func removingHTMLEntities() -> String {
        var result = self
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "/&gt;", with: ">")
        result = result.replacingOccurrences(of: "/&lt;", with: "<")
        return result
    }
}
