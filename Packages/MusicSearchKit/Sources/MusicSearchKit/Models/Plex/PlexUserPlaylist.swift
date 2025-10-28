import Foundation

public struct PlexUserPlaylistContainer: Codable {
    let size: Int
    let metadata: [PlexUserPlaylist]

    enum CodingKeys: String, CodingKey {
        case size
        case metadata = "Metadata"
    }
}

public struct PlexUserPlaylist: Codable {
    public let ratingKey: String
    public let key: String
    public let guid: String
    public let type: String
    public let title: String
    public let titleSort: String?
    public let summary: String?
    public let viewCount: Int?
    public let lastViewedAt: Int?
    public let duration: Int?
    public let addedAt: Int
    public let updatedAt: Int
    public let composite: String?
    public let thumb: String?
    public var leafCount: Int?

    public var sonosID: String?
    public var thumbImageURL: URL?
}
