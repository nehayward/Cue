import Foundation

public struct PlexSongItem: Codable {
    public let size: Int
    public let allowSync: Bool
    public let librarySectionID: Int
    public let librarySectionTitle: String
    public let metadata: [PlexMetadata]?

    enum CodingKeys: String, CodingKey {
        case size, allowSync, librarySectionID, librarySectionTitle
        case metadata = "Metadata"
    }
}
