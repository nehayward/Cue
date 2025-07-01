import Foundation

public struct PlexArtistAlbumsContainer: Codable {
    public let size: Int
    public let allowSync: Bool
    public let identifier: String
    public let librarySectionID: Int
    public let librarySectionTitle: String
    public let librarySectionUUID: String
    public let mediaTagPrefix: String
    public let mediaTagVersion: Int
    public let metadata: [PlexArtistMetadata]?
    
    enum CodingKeys: String, CodingKey {
        case size
        case allowSync
        case identifier
        case librarySectionID
        case librarySectionTitle
        case librarySectionUUID
        case mediaTagPrefix
        case mediaTagVersion
        case metadata = "Metadata"
    }
}

public struct PlexArtistMetadata: Codable {
    public let ratingKey: String
    public let key: String
    public let type: String
    public let title: String
    public let librarySectionTitle: String
    public let librarySectionID: Int
    public let librarySectionKey: String
    public let index: Int
    public let lastViewedAt: Int?
    public let thumb: String?
    public let addedAt: Int
    public let related: PlexRelated?
    
    public var sonosID: String?
    public var thumbImageURL: URL?
    
    enum CodingKeys: String, CodingKey {
        case ratingKey
        case key
        case type
        case title
        case librarySectionTitle
        case librarySectionID
        case librarySectionKey
        case index
        case lastViewedAt
        case thumb
        case addedAt
        case related = "Related"
    }
}

public struct PlexRelated: Codable {
    public let hub: [PlexAlbumHub]?
    
    enum CodingKeys: String, CodingKey {
        case hub = "Hub"
    }
}

public struct PlexAlbumHub: Codable {
    public let hubKey: String?
    public let key: String?
    public let title: String
    public let type: String
    public let hubIdentifier: String?
    public let context: String?
    public let size: Int
    public let more: Bool?
    public let style: String?
    public let metadata: [PlexAlbumItem]?
    
    enum CodingKeys: String, CodingKey {
        case hubKey
        case key
        case title
        case type
        case hubIdentifier
        case context
        case size
        case more
        case style
        case metadata = "Metadata"
    }
} 
