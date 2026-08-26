import Foundation

public final class MusicServiceParser {
    public typealias TrackID = String
    public static let shared = MusicServiceParser()
    
    // Pre-compiled regex patterns for performance
    private let tidalPattern = #/track\/(\d{7,9})/#
    private let appleSongPattern = #/song:(\w*)/#
    private let appleLibraryPattern = #/librarytrack:(.*?)\?/#
    private let spotifyPattern = #/spotify:track:(\w+)|track:(\w+)/#
    private let soundcloudPattern = #/soundcloud:tracks:(\d+)/#
    private let deezerPattern = #/deezer:tracks:(\d+)|tr-[a-z]+:(\d+)/#
    private let tuneinPattern = #/:(.*?)\?/#
    private let subsonicPattern = #/[?&]id=([^&]+)/#
    private lazy var plexRegex = try? NSRegularExpression(pattern: "([^:]+:\\d+:\\d+)")
    
    public func lookup(uri: String, serviceID: String, type: ContentType) -> (MusicService, TrackID, ContentType)? {
        var service = serviceLookup(serviceID: serviceID)
        if service == .unknown {
            let decoded = uri.removingPercentEncoding ?? uri
            service = identifyService(from: uri, decoded: decoded)
        }
        guard service != .unknown,
              let (id, lookupType) = parse(uri: uri, service: service) else { return nil }
        return (service, id, lookupType ?? type)
    }
    
    private func serviceLookup(serviceID: String) -> MusicService {
        switch serviceID {
        case "12":
            return .spotify
        case "local-library", "65435":
            return .library
        case "204":
            return .apple
        case "160":
            return .soundcloud
        case "2", "519", "250":
            return .deezer
        case "212":
            return .plex
        case "174":
            return .tidal
        case "303":
            return .sonosRadio
        case "236":
            return .pandora
        default:
            return .unknown
        }
    }
    
    public func parse(uri: String, service: MusicService) -> (TrackID, ContentType?)? {
        switch service {
        case .spotify:
            let components = uri.components(separatedBy: ":")
            guard let last = components.last else { return nil }
            return (last, nil)
        case .tidal:
            let components = uri.components(separatedBy: "/")
            guard let last = components.last else { return nil }
            return (last, nil)
        case .apple:
            let components = uri.components(separatedBy: ":")
            guard let last = components.last else { return nil }
            return (last, ContentType(components.first))
        case .soundcloud:
            let components = uri.components(separatedBy: ":")
            guard let last = components.last else { return nil }
            return (last, nil)
        case .deezer:
            // Handles track (tr-flac:ID), album (0004006calbum-ID), playlist (0006006cplaylist_spotify%3Aplaylist-ID)
            let decoded = uri.removingPercentEncoding ?? uri
            if decoded.contains("playlist") {
                guard let id = decoded.components(separatedBy: "-").last, !id.isEmpty else { return nil }
                return (id, .playlist)
            } else if decoded.contains("album") {
                guard let id = decoded.components(separatedBy: "-").last, !id.isEmpty else { return nil }
                return (id, .album)
            } else {
                // track: tr-flac:ID or tr-mp3:ID
                guard let id = decoded.components(separatedBy: ":").last?.components(separatedBy: "?").first, !id.isEmpty else { return nil }
                return (id, .track)
            }
        case .plex:
            return (uri, nil)
        case .subsonic:
            // Stream URL — the song id is the `id` query parameter.
            let id = extractSubsonicTrackID(from: uri.removingPercentEncoding ?? uri)
            guard !id.isEmpty else { return nil }
            return (id, .track)
        case .library:
            return (uri, nil)
        default:
            return nil
        }
    }
    
    public func parse(xml: String, trackURI: String) -> (MusicService, TrackID) {
        guard let decodedURI = trackURI.removingPercentEncoding else { return (.unknown, "") }
        let service = identifyService(from: trackURI, decoded: decodedURI, xml: xml)
        let trackID = extractTrackID(from: decodedURI, for: service)
        return (service, trackID)
    }
    
    // MARK: - Service Identification
    
    private func identifyService(from uri: String, decoded decodedURI: String, xml: String? = nil) -> MusicService {
        // Fast path checks first (no allocation)
        if uri == "333" { return .tuneIn }
        if uri == "303" { return .sonosRadio }
        if uri == "236" { return .pandora }

        // The `sid=` parameter is authoritative, so it has to beat the
        // positional heuristics below. Pandora's per-track stream id carries a
        // `::<sequence>::` field —
        // `VC1::ST::ST:<station>::TR:<track>::3::RINCON_…` on the 4th track of
        // a station — which satisfied Plex's `:3:` check and flipped the whole
        // player to Plex mid-station.
        if uri.range(of: "sid=303", options: .caseInsensitive) != nil || xml?.contains("Svc77575") == true {
            return .sonosRadio
        }
        if uri.range(of: "sid=236", options: .caseInsensitive) != nil || xml?.contains("Svc60423") == true {
            return .pandora
        }

        // Subsonic tracks are plain HTTP hits on the server's REST stream
        // endpoint. Checked before the positional `:3:` Plex heuristic so a
        // server address containing that shape can't flip the player to Plex.
        if decodedURI.contains("/rest/stream") { return .subsonic }

        if decodedURI.contains(":3:") { return .plex }

        // Check XML before lowercasing URI
        if let xml = xml, xml.range(of: "tunein", options: .caseInsensitive) != nil {
            return .tuneIn
        }
        
        // Single lowercased allocation
        let normalized = uri.lowercased()
        
        // Ordered by likelihood/specificity — deezer playlist format contains "spotify" so check first
        if normalized.contains("playlist_spotify") { return .deezer }
        if normalized.contains("spotify") { return .spotify }
        if normalized.contains("airplay") { return .airplay }
        if normalized.contains("x-file-cifs") { return .library }
        if normalized.contains("soundcloud") { return .soundcloud }
        if normalized.contains("deezer") || normalized.contains("tr-flac") || normalized.contains("tr-mp3") { return .deezer }
        if xml?.contains("RINCON519") == true { return .deezer }
        // sid/account checks for both already ran above; these are the weaker
        // name hints, kept below `:3:` so a Plex path containing "pandora"
        // still resolves as Plex.
        if normalized.contains("pandora") { return .pandora }
        
        // Check for Tidal (pattern match only if string contains hint)
        if normalized.contains("tidal") || (try? tidalPattern.firstMatch(in: decodedURI)) != nil {
            return .tidal
        }
        
        // Apple Music (check both patterns in one condition)
        if normalized.contains("librarytrack") || normalized.contains("song") { return .apple }
        
        return .unknown
    }
    
    // MARK: - Track ID Extraction
    
    private func extractTrackID(from uri: String, for service: MusicService) -> TrackID {
        switch service {
        case .apple: return extractAppleTrackID(from: uri)
        case .spotify: return extractSpotifyTrackID(from: uri)
        case .tidal: return extractTidalTrackID(from: uri)
        case .plex: return extractPlexTrackID(from: uri)
        case .soundcloud: return extractSoundCloudID(from: uri)
        case .deezer: return extractDeezerTrackID(from: uri)
        case .tuneIn: return extractTuneInTrackID(from: uri)
        // Sonos Radio and Pandora streams are `x-sonosapi-radio:<id>?...`; the
        // TuneIn extractor (":(.*?)?") recovers the prefixed station id
        // (e.g. sonos:2997, ST:12345).
        case .sonosRadio, .pandora: return extractTuneInTrackID(from: uri)
        case .subsonic: return extractSubsonicTrackID(from: uri)
        case .library, .unknown: return uri
        case .airplay: return ""
        }
    }

    private func extractSubsonicTrackID(from uri: String) -> TrackID {
        if let result = try? subsonicPattern.firstMatch(in: uri) {
            return String(result.1)
        }
        return ""
    }
    
    private func extractAppleTrackID(from uri: String) -> TrackID {
        if let result = try? appleSongPattern.firstMatch(in: uri) {
            return String(result.1)
        }
        
        if let result = try? appleLibraryPattern.firstMatch(in: uri) {
            let id = String(result.1)
            let dotCount = id.reduce(0) { $0 + ($1 == "." ? 1 : 0) }
            
            if dotCount > 1, let dotRange = id.range(of: ".", options: .backwards) {
                return String(id[..<dotRange.lowerBound])
            }
            return id
        }
        
        return ""
    }
    
    private func extractSpotifyTrackID(from uri: String) -> TrackID {
        let targetURI = uri
        // Handle x-sonos-vli format (e.g., "x-sonos-vli:RINCON_...:2,spotify:28099c6bb26870fe799d4e6daf684823")
        if uri.contains("x-sonos-vli:") && uri.contains(",") {
            return ""
        }
        
        if let result = try? spotifyPattern.firstMatch(in: uri) {
            return String(result.1 ?? result.2 ?? "")
        }
        
        return ""
    }
    
    private func extractTidalTrackID(from uri: String) -> TrackID {
        if let result = try? tidalPattern.firstMatch(in: uri) {
            return String(result.1)
        }
        return ""
    }
    
    private func extractPlexTrackID(from uri: String) -> TrackID {
        guard let regex = plexRegex,
              let match = regex.firstMatch(in: uri, range: NSRange(uri.startIndex..., in: uri)),
              let range = Range(match.range, in: uri)
        else { return "" }
        
        return String(uri[range]).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
    }
    
    private func extractSoundCloudID(from uri: String) -> TrackID {
        if let result = try? soundcloudPattern.firstMatch(in: uri) {
            return String(result.1)
        }
        return ""
    }

    private func extractDeezerTrackID(from uri: String) -> TrackID {
        if let result = try? deezerPattern.firstMatch(in: uri) {
            return String(result.1 ?? result.2 ?? "")
        }
        return ""
    }
    
    private func extractTuneInTrackID(from uri: String) -> TrackID {
        if let result = try? tuneinPattern.firstMatch(in: uri) {
            return String(result.1)
        }
        return ""
    }
}
