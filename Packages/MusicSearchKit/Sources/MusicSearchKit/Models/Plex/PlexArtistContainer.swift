import Foundation

struct PlexArtistContainer: Codable {
    let size: Int
    let allowSync: Bool
    let identifier: String
    let librarySectionID: Int
    let librarySectionTitle: String
    let librarySectionUUID: String
    let mediaTagPrefix: String
    let mediaTagVersion: Int
    let metadata: [PlexMetadata]

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
