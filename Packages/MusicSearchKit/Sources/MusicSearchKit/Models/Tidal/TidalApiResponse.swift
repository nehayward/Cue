// Add these new models to decode the JSON response
struct TidalApiResponse: Codable {
    let included: [TidalIncluded]
}

struct TidalApiData: Codable {
    let relationships: TidalRelationships
}

struct TidalRelationships: Codable {
    let albums: TidalRelationship
    let artists: TidalRelationship
    let tracks: TidalRelationship
    let playlists: TidalRelationship // Add this line
}

struct TidalRelationship: Codable {
    let data: [TidalRelationshipData]
}

struct TidalRelationshipData: Codable {
    let id: String
    let type: String
}

struct TidalIncluded: Codable {
    let id: String
    let type: String
    let attributes: TidalAttributes
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
    let copyright: String?
    
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
    
    // Content type
    let type: String?
    
    var label: String {
        [title, name].compactMap { $0 }.first ?? ""
    }
    
    var popularityRating: Double {
        popularity ?? 0
    }
    
    var tidalImages: [TidalImage] {
        imageLinks?.compactMap { TidalImage(url: $0.href, width: $0.meta.width, height: $0.meta.height)} ?? []
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



struct TidalImageMeta: Codable {
    let width: Int
    let height: Int
}


extension TidalApiResponse {
    var toTidalResult: TidalResult {
        // Helper function to find included item by id and type
        func findIncluded(id: String, type: String) -> TidalIncluded? {
            return self.included.first { $0.id == id && $0.type == type }
        }
        
        // Map albums
        let albums: [TidalAlbumResource] = self.included.compactMap {
            guard $0.type.contains("album") else { return nil }
            print($0.type)
            return TidalAlbumResource(
                id: $0.id,
                barcodeId: $0.attributes.barcodeId,
                title: $0.attributes.title ?? "",
                artists: [],
                duration: $0.attributes.durationInSeconds,
                releaseDate: $0.attributes.releaseDate,
                imageCover: $0.attributes.imageLinks?.compactMap { TidalImage(url: $0.href, width: $0.meta.width, height: $0.meta.height)},
                numberOfVolumes: $0.attributes.numberOfVolumes,
                numberOfTracks: $0.attributes.numberOfItems,
                numberOfVideos: nil,
                copyright: nil,
                tidalUrl: $0.attributes.externalLinks?.first?.href?.description ?? "",
                properties: nil,
                mediaMetadata: $0.attributes.mediaTags,
                isExplicit: $0.attributes.isExplicit,
                popularity: $0.attributes.popularityRating
            )
        }

        // Map Artists
        let artists: [TidalArtistResource] = self.included.compactMap {
            guard $0.type == "artists" else { return nil }
            print($0.type)
            
            return TidalArtistResource(
                id: $0.id,
                name: $0.attributes.name ?? "",
                picture: $0.attributes.imageLinks?.compactMap { TidalImage(url: $0.href, width: $0.meta.width, height: $0.meta.height)} ?? [],
                main: false,
                tidalUrl: $0.attributes.externalLinks?.first?.href?.description ?? "",
                popularity: $0.attributes.popularity ?? 0.0
            )
        }
        

        // Map tracks
        let tracks: [TidalTrackResource] = self.included.compactMap {
            guard $0.type == "tracks" else { return nil }
            print($0.type)
            
            return TidalTrackResource(
                id: $0.id,
                isrc: $0.attributes.isrc,
                title: $0.attributes.title ?? "",
                artists: [],
                album: nil,
                duration: $0.attributes.durationInSeconds,
                releaseDate: $0.attributes.releaseDate,
                imageCover: nil,
                numberOfVolumes: nil,
                numberOfTracks: nil,
                numberOfVideos: nil,
                copyright: nil,
                tidalUrl: "",
                mediaMetadata: $0.attributes.mediaTags,
                isExplicit: $0.attributes.isExplicit,
                popularity: $0.attributes.popularityRating
            )
        }
        
        let playlists: [TidalPlaylistResource] = self.included.compactMap {
            guard $0.type == "playlists",
                  let id = $0.attributes.tidalURL.components(separatedBy: "/").last else { return nil }
            
            return TidalPlaylistResource(
                id: id,
                name: $0.attributes.name ?? "",
                description: $0.attributes.description,
                numberOfTracks: $0.attributes.numberOfItems,
                duration: $0.attributes.durationInSeconds,
                imageUrls: $0.attributes.tidalImages,
                tidalUrl: $0.attributes.tidalURL
            )
        }
        
        return TidalResult(albums: albums, artists: artists, tracks: tracks, playlists: playlists)
    }
}
