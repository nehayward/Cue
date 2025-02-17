import Foundation

final class PlaylistParser {
    
    func parsePlaylists(IP: String, xml: String) -> [PlayableContent] {
        var tracks: [PlayableContent] = []
        
        // First extract the Result content from SOAP envelope
        let resultPattern = "<Result>(.*?)</Result>"
        guard let regex = try? NSRegularExpression(pattern: resultPattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let resultRange = Range(match.range(at: 1), in: xml) else {
            return []
        }
        
        let didlContent = String(xml[resultRange]).unescaped
        
        // Now parse each item
        let itemPattern = "<container.*?</container>"
        let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: [.dotMatchesLineSeparators])
        guard let itemMatches = itemRegex?.matches(in: didlContent, range: NSRange(didlContent.startIndex..., in: didlContent)) else {
            return []
        }
        
        for itemMatch in itemMatches {
            guard let itemRange = Range(itemMatch.range, in: didlContent) else { continue }
            let itemXML = String(didlContent[itemRange])
            
            // Extract required fields
            let title = extract(field: "dc:title", from: itemXML) ?? ""
            let contentType = ContentType(extract(field: "upnp:class", from: itemXML) ?? "") ?? .playlist
            
            // Extract resource URI and duration
            guard let id = extract(field: "res", from: itemXML) else { continue }
            
            let mediaContent = MediaContent(service: .library,
                                            id: id,
                                            type: contentType,
                                            location: nil)
        
            
            let content = PlayableContent(title: title,
                                          subtitle: "",
                                          thumbnail: extractAlbumArtURL(IP: IP, xml: itemXML),
                                          artwork: extractAlbumArtURL(IP: IP, xml: itemXML),
                                          content: mediaContent)
            
            tracks.append(content)
        }
        
        return tracks
    }
    
    func parsePlaylistsTracks(IP: String, xml: String) -> [PlayableContent] {
        var tracks: [PlayableContent] = []
        
        // First extract the Result content from SOAP envelope
        let resultPattern = "<Result>(.*?)</Result>"
        guard let regex = try? NSRegularExpression(pattern: resultPattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let resultRange = Range(match.range(at: 1), in: xml) else {
            return []
        }
        
        let didlContent = String(xml[resultRange]).unescaped
        
        // Now parse each item
        let itemPattern = "<item.*?</item>"
        let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: [.dotMatchesLineSeparators])
        guard let itemMatches = itemRegex?.matches(in: didlContent, range: NSRange(didlContent.startIndex..., in: didlContent)) else {
            return []
        }
        
        for itemMatch in itemMatches {
            guard let itemRange = Range(itemMatch.range, in: didlContent) else { continue }
            let itemXML = String(didlContent[itemRange])
            
            // Extract required fields
            let title = extract(field: "dc:title", from: itemXML) ?? ""
            let artist = extract(field: "dc:creator", from: itemXML) ?? ""
            let album = extract(field: "upnp:album", from: itemXML) ?? ""
            let contentType = ContentType(extract(field: "upnp:class", from: itemXML) ?? "") ?? .track
            
            // Extract resource URI and duration
            let resourceURI = extract(field: "res", from: itemXML) ?? ""
            let durationStr = extractAttribute(name: "duration", from: itemXML) ?? ""
            let duration = TimeParser.shared.parseDuration(durationStr)
            
            let (musicServiceType, trackID) = MusicServiceParser().parse(xml: itemXML.unescaped, trackURI: resourceURI)

            let mediaContent = MediaContent(service: musicServiceType,
                                            id: trackID,
                                            type: contentType,
                                            location: nil)
            
            let metadata = PlayableContentMetadata(duration: duration,
                                                   artist: artist,
                                                   album: album)
            
            let content = PlayableContent(title: title,
                                          subtitle: [artist, album].filter { !$0.isEmpty }.joined(separator: " • "),
                                          thumbnail: extractAlbumArtURL(IP: IP, xml: itemXML),
                                          artwork: extractAlbumArtURL(IP: IP, xml: itemXML),
                                          content: mediaContent,
                                          metadata: metadata)
            
            tracks.append(content)
        }
        
        return tracks
    }
    
    // Helper functions
    private func extract(field: String, from xml: String) -> String? {
        let pattern: String
        if field == "res" {
            // Special handling for res tag to extract content between tags
            pattern = "<res[^>]*>(.*?)</res>"
        } else {
            pattern = "<\(field)>(.*?)</\(field)>"
        }
        
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        return String(xml[range])
    }
    
    private func extractAttribute(name: String, from xml: String) -> String? {
        let pattern = "\(name)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        return String(xml[range])
    }
    
    private func extractAlbumArtURL(IP: String, xml: String) -> URL? {
        guard let artURI = extract(field: "upnp:albumArtURI", from: xml) else { return nil }
        return URL(string: "http://\(IP):1400\(artURI.unescaped)")
    }
}
