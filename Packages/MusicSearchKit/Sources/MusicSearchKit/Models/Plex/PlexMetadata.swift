import Foundation

public struct PlexMetadata: Codable {
    public let ratingKey: String
    public let key: String
    public let parentRatingKey: String?
    public let grandparentRatingKey: String?
    public let grandparentTitle: String?
    public let grandparentGuid: String?
    public let grandparentKey: String?
    public let grandparentThumb: String?
    public let grandparentArt: String?
    public let guid: String
    public let parentGuid: String?
    public let parentStudio: String?
    public let type: String
    public let title: String
    public let parentKey: String?
    public let parentTitle: String?
    public let originalTitle: String?
    public let summary: String
    public let index: Int?
    public let parentIndex: Int?
    public let ratingCount: Int?
    public let parentYear: Int?
    public let year: Int?
    public let thumb: String
    public let art: String?
    public let parentThumb: String?
    public let duration: Int?
    public let addedAt: Int?
    public let updatedAt: Int?
    public let media: [PlexMedia]?

    public var sonosID: String?
    public var thumbImageURL: URL?

    enum CodingKeys: String, CodingKey {
        case ratingKey, key, parentRatingKey, grandparentRatingKey, guid, parentGuid, grandparentGuid, parentStudio, type, title, grandparentKey, parentKey, grandparentTitle, parentTitle, originalTitle, summary, index, parentIndex, ratingCount, parentYear, year, thumb, art, parentThumb, grandparentThumb, grandparentArt, duration, addedAt, updatedAt
        case media = "Media"
    }
}
