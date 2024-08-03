import Foundation

public struct PlexPlaylistItem: Codable {
    public let size: Int
    public let totalSize: Int?
    public let ratingKey: String
    public let duration: Int?
    public let title: String
    public let metadata: [PlexMetadata]

    enum CodingKeys: String, CodingKey {
        case size
        case totalSize
        case ratingKey
        case duration
        case title
        case metadata = "Metadata"
    }
}
