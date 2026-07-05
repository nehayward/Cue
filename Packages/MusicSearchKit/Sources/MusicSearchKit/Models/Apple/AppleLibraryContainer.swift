import Foundation

public struct AppleLibraryContainer: Codable {
    public let data: [AppleLibraryItem]
    public let meta: AppleLibraryItem.Meta?
    public let next: String?

    public init(data: [AppleLibraryItem], meta: AppleLibraryItem.Meta?, next: String?) {
        self.data = data
        self.meta = meta
        self.next = next
    }
}

// MARK: - Radio Search Response
public struct AppleRadioSearchResponse: Codable {
    public let results: AppleRadioSearchResults
}

public struct AppleRadioSearchResults: Codable {
    public let stations: AppleRadioStations?
}

public struct AppleRadioStations: Codable {
    public let href: String
    public let next: String?
    public let data: [AppleLibraryItem]
}

public struct AppleLibraryItem: Codable {
    public let id: String
    public let href: String
    public let type: String
    public let attributes: Attributes
    public let relationships: Relationships?

    public var songURL: URL? {
        return URL(string: "https://music.apple.com/us/song/\(id)")
    }

    /// A short preview clip for the track. Catalog items carry `previews`
    /// directly; library items only carry them via the included `catalog`
    /// relationship (requested with `include=catalog`), since the library API
    /// itself omits previews.
    public var previewURL: URL? {
        let previews = attributes.previews ?? relationships?.catalog?.data.first?.attributes.previews
        guard let urlString = previews?.first?.url else { return nil }
        return URL(string: urlString)
    }
}

extension AppleLibraryItem {
    public struct Attributes: Codable {
        public let name: String?
        public let artwork: AppleLibraryArtwork?
        public let playParams: PlayParameters?
        
        public let albumName: String?
        public let genreNames: [String]?
        public let trackNumber: Int?
        public let durationInMillis: Int?
        public let releaseDate: String?
        public let artistName: String?
        public let contentRating: String?
        public let isLive: Bool?
        public let previews: [Preview]?

        public var releaseDateFormatted: String? {
            if let releaseDate {
                return releaseDate.components(separatedBy: "-").first
            }
            return nil
        }
    }

    public struct Meta: Codable {
        public let total: Int?
    }

    public struct PlayParameters: Codable {
        public let catalogID: String?
        public let id: String
        public let kind: String
    }

    public struct Relationships: Codable {
        public let catalog: AppleLibraryContainer?
    }

    public struct Preview: Codable {
        public let url: String
    }
}

// MARK: - Recommendations Response Models
public struct AppleRecommendationsResponse: Codable {
    public let data: [PersonalRecommendation]
    public let next: String?
}

public struct PersonalRecommendation: Codable {
    public let id: String
    public let type: String
    public let href: String
    public let attributes: RecommendationAttributes
    public let relationships: RecommendationRelationships
}

public struct RecommendationAttributes: Codable {
    public let isGroupRecommendation: Bool
    public let resourceTypes: [String]
    public let nextUpdateDate: String
    public let title: RecommendationTitle
    public let kind: String
}

public struct RecommendationTitle: Codable {
    public let stringForDisplay: String
}

public struct RecommendationRelationships: Codable {
    public let contents: RecommendationContents
}

public struct RecommendationContents: Codable {
    public let href: String
    public let data: [AppleLibraryItem]
}
