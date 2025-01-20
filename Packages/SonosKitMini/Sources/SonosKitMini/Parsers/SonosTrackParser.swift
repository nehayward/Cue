import Foundation

// Your imports remain the same
final class SonosTrackParser {
    // Function to parse the full XML response
    static func parse(xmlString: String, ip: String, preferredIP: String?) -> SonosTrack? {
        // First extract the body content
        guard let bodyContent = extractValue(between: "<s:Body>", and: "</s:Body>", from: xmlString) else {
            return nil
        }
        
        // Extract transport state
        let transportState = extractValue(from: bodyContent, forTag: "TransportState")
        let currentPlayMode = extractValue(from: bodyContent, forTag: "CurrentPlayMode")
        let numberOfTracks = Int(extractValue(from: bodyContent, forTag: "NumberOfTracks") ?? "0") ?? 0
        let currentTrack = Int(extractValue(from: bodyContent, forTag: "CurrentTrack") ?? "0") ?? 0
        let currentTrackDuration = extractValue(from: bodyContent, forTag: "CurrentTrackDuration")
        
        // Extract track information
        let track = Int(extractValue(between: "<Track>", and: "</Track>", from: bodyContent) ?? "0") ?? 0
        let trackDuration = extractValue(between: "<TrackDuration>", and: "</TrackDuration>", from: bodyContent)
        let trackURI = extractValue(between: "<TrackURI>", and: "</TrackURI>", from: bodyContent)
        
        // Extract metadata section
        guard let metadataContent = extractValue(between: "<TrackMetaData>", and: "</TrackMetaData>", from: bodyContent.unescaped),
              let itemContent = extractValue(between: "<item", and: "</item>", from: metadataContent) else {
            return nil
        }
        
        // Parse track metadata
        let title = extractValue(between: "<dc:title>", and: "</dc:title>", from: itemContent) ?? ""
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
//
//        let ip = preferredIP ?? ip
//        // First replace HTML entities
//        let decodedAmpersand = albumArtURI.replacingOccurrences(of: "&amp;", with: "&")
//
//        // Then decode percent encoding and URL encoding
//        let decodedUrl = decodedAmpersand
//            .removingPercentEncoding?
//            .replacingOccurrences(of: "%3a", with: ":")
//            .replacingOccurrences(of: "%3f", with: "?")
//            .replacingOccurrences(of: "%3d", with: "=")
//            .replacingOccurrences(of: "%26", with: "&")
//        
//        var sonosAlbumArtURL: URL?
//        
//        if let decodedUrl, !decodedUrl.isEmpty {
//            sonosAlbumArtURL = URL(string: "http://\(ip):1400\(decodedUrl)")
//        }
        
        let (musicServiceType, trackID) = MusicServiceParser().parse(xml: bodyContent.unescaped, trackURI: trackURI ?? "")

        return SonosTrack(
            trackID: trackID,
            name: title,
            artist: creator,
            album: album,
            musicService: musicServiceType,
            duration: .zero,
            playbackPosition: .zero,
            position: 1,
            metadata: nil,
            albumArtURI: albumArtURI
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
