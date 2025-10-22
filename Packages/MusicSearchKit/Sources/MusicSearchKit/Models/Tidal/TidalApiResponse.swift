// Add these new models to decode the JSON response
struct TidalApiResponse: Codable {
    let included: [TidalIncluded]
    let data: TidalApiData?
    let links: TidalLinks?
}

struct TidalApiResponsePlaylistItems: Codable {
    let included: [TidalIncluded]
    let data: [TidalApiData]
    let links: TidalLinks?
}

struct TidalLinks: Codable {
    let meta: TidalMetadata?
}

struct TidalMetadata: Codable {
    let nextCursor: String?
}

struct TidalApiData: Codable {
    let relationships: TidalRelationships?
    let attributes: TidalAttributes?
}

struct TidalRelationships: Codable {
    let albums: TidalRelationship?
    let artists: TidalRelationship?
    let tracks: TidalRelationship?
    let playlists: TidalRelationship? // Add this line
}

struct TidalRelationship: Codable {
    let data: [TidalRelationshipData]?
}

struct TidalRelationshipData: Codable {
    let id: String
    let type: String
}

struct TidalIncluded: Codable {
    let id: String
    let type: String
    let attributes: TidalAttributes?
    let relationships: TidalItemRelationships?
}

struct TidalItemRelationships: Codable {
    let coverArt: TidalRelationship?
    let profileArt: TidalRelationship?
}

struct TidalAttributes: Codable {
    // Basic info
    let title: String?
    let name: String?
    let description: String?
    
    // Media details
    let barcodeId: String?
    let numberOfVolumes: Int?
    let numberOfItems: Int?
    let duration: String?
    private let explicit: Bool?
    let releaseDate: String?
    let copyright: Copyright?
    
    // Stats and metadata
    let popularity: Double?
    let availability: [String]?
    let mediaTags: [String]?
    
    // Track-specific fields
    let isrc: String?
    
    // Links
    let imageLinks: [TidalImageLink]?
    let videoLinks: [TidalExternalUrls]?
    let externalLinks: [TidalExternalUrls]?
    
    // Artwork-specific fields
    let mediaType: String?
    let files: [TidalImageLink]?
    
    // Content type
    let type: String?
    
    var label: String {
        [title, name].compactMap { $0 }.first ?? ""
    }
    
    var popularityRating: Double {
        popularity ?? 0
    }
    
    var tidalImages: [TidalImage] {
        let links = files ?? imageLinks ?? []
        return links.compactMap { TidalImage(url: $0.href, width: $0.meta.width, height: $0.meta.height) }
    }
    
    var tidalURL: String {
        externalLinks?.first?.href ?? ""
    }
    
    var isExplicit: Bool {
        explicit ?? false
    }
}

extension TidalAttributes {
    var durationInSeconds: Int {
        guard let duration = duration else { return 0 }
        
        // Remove the PT prefix
        let timeString = duration.replacingOccurrences(of: "PT", with: "")
        
        var seconds = 0
        
        // Extract hours if present (H)
        if let hourRange = timeString.range(of: "\\d+H", options: .regularExpression) {
            let hourString = timeString[hourRange].dropLast()
            seconds += (Int(hourString) ?? 0) * 3600
        }
        
        // Extract minutes if present (M)
        if let minuteRange = timeString.range(of: "\\d+M", options: .regularExpression) {
            let minuteString = timeString[minuteRange].dropLast()
            seconds += (Int(minuteString) ?? 0) * 60
        }
        
        // Extract seconds if present (S)
        if let secondRange = timeString.range(of: "\\d+S", options: .regularExpression) {
            let secondString = timeString[secondRange].dropLast()
            seconds += Int(secondString) ?? 0
        }
        
        return seconds
    }
}

struct TidalExternalUrls: Codable {
    let href: String?
}

struct TidalImageLink: Codable {
    let href: String
    let meta: TidalImageMeta
}

// Nested struct for copyright
public struct Copyright: Codable {
    public let text: String
}

struct TidalImageMeta: Codable {
    let width: Int
    let height: Int
}


extension TidalApiResponse {
    var toTidalResult: TidalResult {
        // Build efficient lookup dictionaries - O(n) setup for O(1) lookups
        var artworkLookup: [String: TidalIncluded] = [:]
        var albumsData: [TidalIncluded] = []
        var artistsData: [TidalIncluded] = []
        var tracksData: [TidalIncluded] = []
        var playlistsData: [TidalIncluded] = []
        
        // Single pass through included array to categorize items
        for item in included {
            switch item.type {
            case "artworks":
                artworkLookup[item.id] = item
            case let type where type.contains("album"):
                albumsData.append(item)
            case "artists":
                artistsData.append(item)
            case "tracks":
                tracksData.append(item)
            case "playlists":
                playlistsData.append(item)
            default:
                break
            }
        }
        
        // Helper to get artwork images from relationship
        func getArtwork(from relationship: TidalRelationship?) -> [TidalImage] {
            guard let artworkId = relationship?.data?.first?.id,
                  let artwork = artworkLookup[artworkId],
                  let attributes = artwork.attributes else {
                return []
            }
            return attributes.tidalImages
        }
        
        // Map albums with artwork lookup
        let albums: [TidalAlbumResource] = albumsData.compactMap { item in
            guard let attributes = item.attributes else { return nil }
            
            let artwork = getArtwork(from: item.relationships?.coverArt)
            
            return TidalAlbumResource(
                id: item.id,
                barcodeId: attributes.barcodeId,
                title: attributes.title ?? "",
                artists: [],
                duration: attributes.durationInSeconds,
                releaseDate: attributes.releaseDate,
                imageCover: artwork.isEmpty ? nil : artwork,
                numberOfVolumes: attributes.numberOfVolumes,
                numberOfTracks: attributes.numberOfItems,
                numberOfVideos: nil,
                copyright: nil,
                tidalUrl: attributes.tidalURL,
                properties: nil,
                mediaMetadata: attributes.mediaTags,
                isExplicit: attributes.isExplicit,
                popularity: attributes.popularityRating
            )
        }

        // Map artists with artwork lookup
        let artists: [TidalArtistResource] = artistsData.compactMap { item in
            guard let attributes = item.attributes else { return nil }
            
            let artwork = getArtwork(from: item.relationships?.profileArt)
            
            return TidalArtistResource(
                id: item.id,
                name: attributes.name ?? "",
                picture: artwork,
                main: false,
                tidalUrl: attributes.tidalURL,
                popularity: attributes.popularity ?? 0.0
            )
        }

        // Map tracks
        let tracks: [TidalTrackResource] = tracksData.compactMap { item in
            guard let attributes = item.attributes else { return nil }

            return TidalTrackResource(
                id: item.id,
                isrc: attributes.isrc,
                title: attributes.title ?? "",
                artists: [],
                album: nil,
                duration: attributes.durationInSeconds,
                releaseDate: attributes.releaseDate,
                imageCover: nil,
                numberOfVolumes: nil,
                numberOfTracks: nil,
                numberOfVideos: nil,
                copyright: nil,
                tidalUrl: attributes.tidalURL,
                mediaMetadata: attributes.mediaTags,
                isExplicit: attributes.isExplicit,
                popularity: attributes.popularityRating
            )
        }
        
        // Map playlists
        let playlists: [TidalPlaylistResource] = playlistsData.compactMap { item in
            guard let attributes = item.attributes,
                  let id = attributes.tidalURL.components(separatedBy: "/").last else {
                return nil
            }
            
            let artwork = getArtwork(from: item.relationships?.coverArt)
            
            return TidalPlaylistResource(
                id: id,
                name: attributes.name ?? "",
                description: attributes.description,
                numberOfTracks: attributes.numberOfItems,
                duration: attributes.durationInSeconds,
                imageUrls: artwork.isEmpty ? [] : artwork,
                tidalUrl: attributes.tidalURL
            )
        }
        
        return TidalResult(albums: albums, artists: artists, tracks: tracks, playlists: playlists)
    }
}



extension TidalApiResponsePlaylistItems {
    var toTidalResult: TidalResult {
        // Build efficient lookup dictionaries - O(n) setup for O(1) lookups
        var artworkLookup: [String: TidalIncluded] = [:]
        var albumsData: [TidalIncluded] = []
        var artistsData: [TidalIncluded] = []
        var tracksData: [TidalIncluded] = []
        var playlistsData: [TidalIncluded] = []
        
        // Single pass through included array to categorize items
        for item in included {
            switch item.type {
            case "artworks":
                artworkLookup[item.id] = item
            case let type where type.contains("album"):
                albumsData.append(item)
            case "artists":
                artistsData.append(item)
            case "tracks":
                tracksData.append(item)
            case "playlists":
                playlistsData.append(item)
            default:
                break
            }
        }
        
        // Helper to get artwork images from relationship
        func getArtwork(from relationship: TidalRelationship?) -> [TidalImage] {
            guard let artworkId = relationship?.data?.first?.id,
                  let artwork = artworkLookup[artworkId],
                  let attributes = artwork.attributes else {
                return []
            }
            return attributes.tidalImages
        }
        
        // Map albums with artwork lookup
        let albums: [TidalAlbumResource] = albumsData.compactMap { item in
            guard let attributes = item.attributes else { return nil }
            
            let artwork = getArtwork(from: item.relationships?.coverArt)
            
            return TidalAlbumResource(
                id: item.id,
                barcodeId: attributes.barcodeId,
                title: attributes.title ?? "",
                artists: [],
                duration: attributes.durationInSeconds,
                releaseDate: attributes.releaseDate,
                imageCover: artwork.isEmpty ? nil : artwork,
                numberOfVolumes: attributes.numberOfVolumes,
                numberOfTracks: attributes.numberOfItems,
                numberOfVideos: nil,
                copyright: nil,
                tidalUrl: attributes.tidalURL,
                properties: nil,
                mediaMetadata: attributes.mediaTags,
                isExplicit: attributes.isExplicit,
                popularity: attributes.popularityRating
            )
        }

        // Map artists with artwork lookup
        let artists: [TidalArtistResource] = artistsData.compactMap { item in
            guard let attributes = item.attributes else { return nil }
            
            let artwork = getArtwork(from: item.relationships?.profileArt)
            
            return TidalArtistResource(
                id: item.id,
                name: attributes.name ?? "",
                picture: artwork,
                main: false,
                tidalUrl: attributes.tidalURL,
                popularity: attributes.popularity ?? 0.0
            )
        }

        // Map tracks
        let tracks: [TidalTrackResource] = tracksData.compactMap { item in
            guard let attributes = item.attributes else { return nil }
            
            return TidalTrackResource(
                id: item.id,
                isrc: attributes.isrc,
                title: attributes.title ?? "",
                artists: [],
                album: nil,
                duration: attributes.durationInSeconds,
                releaseDate: attributes.releaseDate,
                imageCover: nil,
                numberOfVolumes: nil,
                numberOfTracks: nil,
                numberOfVideos: nil,
                copyright: nil,
                tidalUrl: attributes.tidalURL,
                mediaMetadata: attributes.mediaTags,
                isExplicit: attributes.isExplicit,
                popularity: attributes.popularityRating
            )
        }
        
        // Map playlists
        let playlists: [TidalPlaylistResource] = playlistsData.compactMap { item in
            guard let attributes = item.attributes,
                  let id = attributes.tidalURL.components(separatedBy: "/").last else {
                return nil
            }
            
            let artwork = getArtwork(from: item.relationships?.coverArt)
            
            return TidalPlaylistResource(
                id: id,
                name: attributes.name ?? "",
                description: attributes.description,
                numberOfTracks: attributes.numberOfItems,
                duration: attributes.durationInSeconds,
                imageUrls: artwork.isEmpty ? [] : artwork,
                tidalUrl: attributes.tidalURL
            )
        }
        
        return TidalResult(albums: albums, artists: artists, tracks: tracks, playlists: playlists)
    }
}
