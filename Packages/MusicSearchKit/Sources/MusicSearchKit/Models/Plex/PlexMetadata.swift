import Foundation

public struct PlexMetadata: Codable, Sendable {
    public let ratingKey: String
    public let key: String
    public let playlistItemID: Int?
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
    public let thumb: String?
    public let art: String?
    public let parentThumb: String?
    public let duration: Int?
    public let addedAt: Int?
    public let updatedAt: Int?
    public let viewCount: Int?
    public let lastViewedAt: Int?
    public let userRating: Double?
    /// Track count for album items; distinguishes editions in search rows.
    public let leafCount: Int?
    /// How far into the track playback was left, in milliseconds, as the
    /// timeline reports put it: where an audiobook's file resumes.
    public let viewOffset: Int?
    /// Chapter marks inside the file (an `.m4b`), when asked for with
    /// `includeChapters=1`.
    public let chapters: [PlexChapter]?
    public let media: [PlexMedia]?

    public var sonosID: String?
    public var thumbImageURL: URL?
    public var artImageURL: URL?
    /// Direct, token-authenticated URL to stream the track's media file from the
    /// user's Plex server. Populated by `PlexAPI` for track items (Plex has no
    /// short preview clips, so this is the full file). Drives `previewURL`.
    public var streamURL: URL?

    enum CodingKeys: String, CodingKey {
        case ratingKey, key, playlistItemID, parentRatingKey, grandparentRatingKey, guid, parentGuid, grandparentGuid, parentStudio, type, title, grandparentKey, parentKey, grandparentTitle, parentTitle, originalTitle, summary, index, parentIndex, ratingCount, parentYear, year, thumb, art, parentThumb, grandparentThumb, grandparentArt, duration, addedAt, updatedAt, viewCount, lastViewedAt, userRating, leafCount, viewOffset
        case chapters = "Chapter"
        case media = "Media"
    }
}
