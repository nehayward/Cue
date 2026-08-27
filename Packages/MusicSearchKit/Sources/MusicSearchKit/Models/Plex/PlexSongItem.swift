import Foundation

public struct PlexSongItem: Codable {
    public let size: Int
    /// How many songs the section holds in total, not just in this page.
    public let totalSize: Int?
    public let allowSync: Bool
    public let librarySectionID: Int
    public let librarySectionTitle: String
    public let metadata: [PlexMetadata]?

    enum CodingKeys: String, CodingKey {
        case size, totalSize, allowSync, librarySectionID, librarySectionTitle
        case metadata = "Metadata"
    }
}
