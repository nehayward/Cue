import Foundation

public struct AppleLibraryContainer: Codable {
    public let data: [AppleLibraryItem]
    public let meta: AppleLibraryItem.Meta?
    public let next: String?
}

public struct AppleLibraryItem: Codable {
    public let id: String
    public let href: String
    public let type: String
    public let attributes: Attributes

    public var songURL: URL? {
        return URL(string: "https://music.apple.com/us/song/\(id)")
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
        public let catalog: AppleLibraryContainer
    }
}
