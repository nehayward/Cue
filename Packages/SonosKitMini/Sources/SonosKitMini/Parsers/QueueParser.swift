import Foundation

// Your imports remain the same
final class QueueParser {
    
    // Add parse queue method
    static func parseQueue(xmlString: String, ip: String, preferredIP: String?) -> [PlayableContent] {
        guard let bodyContent = extractValue(between: "<s:Body>", and: "</s:Body>", from: xmlString),
              let resultContent = extractValue(between: "<Result>", and: "</Result>", from: bodyContent),
              let didlContent = extractValue(between: "<DIDL-Lite", and: "</DIDL-Lite>", from: resultContent.unescaped) else {
            return []
        }
        
        // Split into individual items
        let items = didlContent.components(separatedBy: "<item")
            .dropFirst() // First component is empty
            .compactMap { itemContent -> PlayableContent? in
                let fullItemContent = "<item" + itemContent
            
                // Extract track number from item ID
                guard let idString = extractValue(between: "id=\"Q:0/", and: "\"", from: fullItemContent),
                      let number = Int(idString) else {
                    return nil
                }
                
                // Extract full <res> tag content first
                guard let resTag = extractValue(between: "<res", and: "/res>", from: fullItemContent) else {
                    return nil
                }
                
                // Now extract the URI from within the res tag
                guard let trackURI = extractValue(between: ">", and: "</", from: resTag + "</") else {
                    return nil
                }
                
                let title = extractValue(between: "<dc:title>", and: "</dc:title>", from: fullItemContent)?.unescaped ?? ""
                let creator = extractValue(between: "<dc:creator>", and: "</dc:creator>", from: fullItemContent)?.unescaped ?? ""
                let album = extractValue(between: "<upnp:album>", and: "</upnp:album>", from: fullItemContent)?.unescaped ?? ""
                let albumArtURI = extractValue(between: "<upnp:albumArtURI>", and: "</upnp:albumArtURI>", from: fullItemContent) ?? ""
                let duration = extractValue(between: "duration=\"", and: "\"", from: fullItemContent)
                    .map { TimeInterval(durationString: $0) } ?? 0
                
                let (musicServiceType, trackID) = MusicServiceParser().parse(xml: fullItemContent, trackURI: trackURI)
                
                let ip = preferredIP ?? ip
                let sonosAlbumArtURL = URL(string: "http://\(ip):1400\(albumArtURI.unescaped)")
            
                print(number)

                let metadata = PlayableContentMetadata(
                    duration: Duration.milliseconds(duration),
                    artist: "",
                    album: "",
                    position: number
                )
//                
                return PlayableContent(
                    title: title,
                    subtitle: creator,
                    thumbnail: sonosAlbumArtURL,
                    artwork: nil,
                    content: .init(
                        service: .apple,
                        id: trackID,
                        type: .track,
                        location: nil
                    ),
                    metadata: metadata
                )
//                return SonosTrack(
//                    trackID: trackID,
//                    trackURI: trackURI,
//                    name: title,
//                    artist: creator,
//                    album: album,
//                    musicService: musicServiceType,
//                    duration: 0,
//                    playbackPosition: .zero,
//                    position: 1,
//                    sonosAlbumArtURL: sonosAlbumArtURL,
//                    metadata: nil,
//                    albumArtURI: albumArtURI
//                )
            }
        
        return items
    }
    
//    // Helper function to extract values from XML-like strings
//    private static func extractValue(from text: String, forTag tag: String) -> String? {
//        let pattern = "\(tag) val=\"([^\"]*)\""
//        guard let regex = try? NSRegularExpression(pattern: pattern),
//              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
//            return nil
//        }
//        
//        guard let range = Range(match.range(at: 1), in: text) else {
//            return nil
//        }
//        
//        return String(text[range])
//    }
//    
    // Helper function to extract content between two strings
    private static func extractValue(between startTag: String, and endTag: String, from text: String) -> String? {
        guard let range = text.range(of: startTag)?.upperBound,
              let endRange = text[range...].range(of: endTag)?.lowerBound else {
            return nil
        }
        return String(text[range..<endRange])
    }
}

// Add TimeInterval extension for duration parsing
fileprivate extension TimeInterval {
    init(durationString: String) {
        let components = durationString.split(separator: ":")
        let hours = Double(components.count == 3 ? components[0] : "0") ?? 0
        let minutes = Double(components.count == 3 ? components[1] : components[0]) ?? 0
        let seconds = Double(components.count == 3 ? components[2] : components[1]) ?? 0
        
        self = hours * 3600 + minutes * 60 + seconds
    }
}
