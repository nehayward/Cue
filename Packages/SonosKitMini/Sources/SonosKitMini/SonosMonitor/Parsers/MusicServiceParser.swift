import Foundation

final class MusicServiceParser {
    typealias TrackID = String
    
    func parse(xml: String, trackURI: String) -> (SonosMusicServiceType, TrackID) {
        // Early return if we can't decode percent encoding
        guard let decodedURI = trackURI.removingPercentEncoding else {
            return (.unknown, "")
        }
        
        // Determine music service type first
        let serviceType = determineServiceType(from: xml, trackURI: trackURI)
        
        // Extract track ID based on service type
        let trackID = extractTrackID(from: decodedURI, for: serviceType)
        
        return (serviceType, trackID)
    }
    
    // MARK: - Private Methods
    
    private func determineServiceType(from xml: String, trackURI: String) -> SonosMusicServiceType {
        // Handle x-sonos-vli format first (e.g., "x-sonos-vli:RINCON_...:2,spotify:...")
        if trackURI.contains("x-sonos-vli:") && trackURI.contains(",") {
            let components = trackURI.components(separatedBy: ",")
            if components.count > 1 {
                let serviceURI = components[1]
                if serviceURI.contains("spotify") {
                    return .spotify
                } else if serviceURI.contains("apple") || serviceURI.contains("song") {
                    return .apple
                }
            }
        }
        
        // Check in order of most specific to least specific patterns
        switch true {
        case trackURI.contains("airplay"):             return .airplay
        case trackURI.contains("x-file-cifs"):         return .library
        case xml.lowercased().contains("tunein"):      return .tuneIn
        case trackURI.contains("%3a3%3"):             return .plex
        case trackURI.contains("librarytrack"),
             trackURI.contains("song"):                return .apple
        case trackURI.contains("spotify"):             return .spotify
        case isTidalTrack(trackURI):                  return .tidal
        default:                                      return .unknown
        }
    }
    
    private func isTidalTrack(_ uri: String) -> Bool {
        guard let decodedURI = uri.removingPercentEncoding else { return false }
        let tidalPattern = #/track\/(\d{7,9})/#
        return (try? tidalPattern.firstMatch(in: decodedURI)) != nil
    }
    
    private func extractTrackID(from uri: String, for service: SonosMusicServiceType) -> TrackID {
        switch service {
        case .apple:
            return extractAppleTrackID(from: uri)
        case .spotify:
            return extractSpotifyTrackID(from: uri)
        case .tidal:
            return extractTidalTrackID(from: uri)
        case .plex:
            return extractPlexTrackID(from: uri)
        case .library:
            return uri
        case .tuneIn, .airplay, .unknown:
            return ""
        }
    }
    
    private func extractAppleTrackID(from uri: String) -> TrackID {
        let songPattern = #/song:(\w*)/#
        let libraryPattern = #/librarytrack:(.*?)\?/#
        
        if let result = try? songPattern.firstMatch(in: uri) {
            return String(result.1)
        }
        
        if let result = try? libraryPattern.firstMatch(in: uri) {
            let trackID = String(result.1)
            if let dotRange = trackID.range(of: ".", options: .backwards),
               trackID.filter({ $0 == "." }).count > 1 {
                return String(trackID[..<dotRange.lowerBound])
            }
            return trackID
        }
        
        return ""
    }
    
    private func extractSpotifyTrackID(from uri: String) -> TrackID {
        var targetURI = uri
        
        // Handle x-sonos-vli format (e.g., "x-sonos-vli:RINCON_...:2,spotify:28099c6bb26870fe799d4e6daf684823")
        if uri.contains("x-sonos-vli:") && uri.contains(",") {
            let components = uri.components(separatedBy: ",")
            if components.count > 1 {
                targetURI = components[1]
                // For VLI format like "spotify:28099c6bb26870fe799d4e6daf684823", extract just the ID
                if targetURI.hasPrefix("spotify:") && !targetURI.contains("track:") {
                    return String(targetURI.dropFirst("spotify:".count))
                }
            }
        }
        
        // Extract Spotify track ID using regex pattern
        let pattern = #/spotify:track:(\w+)|track:(\w+)/#
        if let result = try? pattern.firstMatch(in: targetURI) {
            // Return the first non-nil capture group
            return String(result.1 ?? result.2 ?? "")
        }
        
        return ""
    }
    
    private func extractTidalTrackID(from uri: String) -> TrackID {
        let pattern = #/track\/(\d{7,9})/#
        if let result = try? pattern.firstMatch(in: uri) {
            return String(result.1)
        }
        return ""
    }
    
    private func extractPlexTrackID(from uri: String) -> TrackID {
        let pattern = "([^:]+:\\d+:\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        
        let results = regex.matches(in: uri, range: NSRange(uri.startIndex..., in: uri))
        guard let match = results.first,
              let range = Range(match.range, in: uri),
              let encoded = String(uri[range]).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return "" }
        
        return encoded
    }
}
