import Foundation

public struct SpotifyAlbums: Decodable, Sendable {
    public let items: [SpotifyAlbumItem?]
}

public struct SpotifyAlbumItem: Equatable, Decodable, Identifiable, Sendable {
    public let id: String?
    public let externalUrls: ExternalUrls?
    public let name: String
    public let isPlayable: Bool?
    public let artists: [SpotifyArtistsInfo]?
    public let images: [SpotifyImage]?
    public let type: String
    public let uri: String?
    public let releaseDate: String?
    public var allArtists: String { artists?.compactMap{ $0.name }.joined(separator: ", ") ?? "Unknown"}
    
    public var releaseDateFormatted: String? {
        if let releaseDate {
            return releaseDate.components(separatedBy: "-").first
        }
        return nil
    }
    
    public var releaseYear: Date? {
        guard let dateString = releaseDate else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: dateString)
    }
    
    public init(id: String, externalUrls: ExternalUrls, name: String, isPlayable: Bool?, artists: [SpotifyArtistsInfo], images: [SpotifyImage], type: String, uri: String, releaseDate: String?) {
        self.id = id
        self.externalUrls = externalUrls
        self.name = name
        self.isPlayable = isPlayable
        self.artists = artists
        self.images = images
        self.type = type
        self.uri = uri
        self.releaseDate = releaseDate
    }
}

public struct SpotifyAlbumDetails: Decodable, Sendable {
    public let href: String
    public let externalUrls: ExternalUrls
    public let name: String
    public let id: String
    public let releaseDate: String
    public let images: [SpotifyImage]
    public let tracks: SpotifyAlbumTracks
    public let artists: [SpotifyArtistsInfo]?
    public var allArtists: String? { artists?.compactMap(\.name).joined(separator: ", ") }
    public let durationMs: Int?
    public let explicit: Bool?
    /// Only present on full album objects (the search API returns simplified
    /// albums without it).
    public let popularity: Int?

    public var releaseDateFormatted: String? {
        return releaseDate.components(separatedBy: "-").first
    }

    /// Albums have no explicit flag of their own; derive it from the tracks
    /// the full album object includes (first page is plenty).
    public var containsExplicitTracks: Bool {
        tracks.items.contains(where: \.explicit)
    }
}

/// Response envelope for the batch `/v1/albums?ids=` endpoint. Spotify
/// returns `null` entries for unknown ids.
public struct SpotifyAlbumsBatch: Decodable, Sendable {
    public let albums: [SpotifyAlbumDetails?]
}

public struct SpotifyAlbumTracks: Decodable, Sendable {
    public let items: [SpotifyAlbumTrackItems]
    /// Spotify's paging metadata for the album's tracks (used to walk albums past the first page).
    public let total: Int?
    public let next: String?
}

public struct SpotifyAlbumTrackItems: Decodable, Identifiable, Sendable {
    public let id: String?
    public let href: String?
    public let name: String
    public let artists: [SpotifyArtistsInfo]
    public let externalUrls: ExternalUrls?
    public let externalIds: SpotifyExternalIDS?
    public let type: String
    public let uri: String
    public let explicit: Bool
    public let durationMs: Int
    public let album: SpotifyAlbumItem?
    public let previewUrl: String?
    public var allArtists: String { artists.map(\.name).joined(separator: ", ") }
}
