import Foundation

public struct PlexLibraryItem: Codable {
    public let size: Int?
    public let allowSync: Bool?
    public let art: String?
    public let grandparentRatingKey: Int?
    public let grandparentThumb: String?
    public let grandparentTitle: String?
    public let identifier: String?
    public let key: String
    public let librarySectionID: Int?
    public let librarySectionTitle: String?
    public let librarySectionUUID: String?
    public let mediaTagPrefix: String?
    public let mediaTagVersion: Int?
    public let nocache: Bool?
    public let parentIndex: Int?
    public let parentTitle: String?
    public let parentYear: Int?
    public let summary: String?
    public let thumb: String?
    public let title1: String?
    public let title2: String?
    public let viewGroup: String?
    public let metadata: [PlexMetadata]?
    
    public var sonosID: String?
    public var thumbImageURL: URL?

    enum CodingKeys: String, CodingKey {
        case size, allowSync, art, grandparentRatingKey, grandparentThumb, grandparentTitle, identifier, key, librarySectionID, librarySectionTitle, librarySectionUUID, mediaTagPrefix, mediaTagVersion, nocache, parentIndex, parentTitle, parentYear, summary, thumb, title1, title2, viewGroup
        case metadata = "Metadata"
    }
}
