import Foundation

public struct PlexAlbumContainer: Codable {
    public let size: Int
    public let totalSize: Int?
    public let offset: Int?
    public let metadata: [PlexAlbumItem]?
    
    enum CodingKeys: String, CodingKey {
        case size
        case totalSize
        case offset
        case metadata = "Metadata"
    }
}

public struct PlexAlbumItem: Codable {
    public var ratingKey: String
    public var key: String
    public var parentRatingKey: String
    public var guid: String
    public var parentGuid: String
    public var studio: String?
    public var type: String
    public var title: String
    public var parentKey: String
    public var parentTitle: String
    public var summary: String
    public var index: Int
    public var rating: Double?
    public var viewCount: Int?
    public var skipCount: Int?
    public var lastViewedAt: Date?
    public var year: Int?
    public var thumb: String?
    public var art: String?
    public var parentThumb: String?
    public var originallyAvailableAt: String?
    public var addedAt: Date
    public var updatedAt: Date
    public var genre: [PlexGenre]?
    
    public var sonosID: String?
    public var thumbImageURL: URL?

    enum CodingKeys: String, CodingKey {
        case ratingKey
        case key
        case parentRatingKey
        case guid
        case parentGuid
        case studio
        case type
        case title
        case parentKey
        case parentTitle
        case summary
        case index
        case rating
        case viewCount
        case skipCount
        case lastViewedAt
        case year
        case thumb
        case art
        case parentThumb
        case originallyAvailableAt
        case addedAt
        case updatedAt
        case genre = "Genre"
    }
    
    public struct PlexGenre: Codable {
        let tag: String
    }
}
