import Foundation

public struct PlexUserPlaylistContainer: Codable {
    let size: Int?
    let metadata: [PlexUserPlaylist]

    enum CodingKeys: String, CodingKey {
        case size
        case metadata = "Metadata"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        // Plex omits `Metadata` entirely for an empty result (e.g. creating an item-less playlist),
        // so default to [] rather than failing the whole decode.
        metadata = try container.decodeIfPresent([PlexUserPlaylist].self, forKey: .metadata) ?? []
    }
}

public struct PlexUserPlaylist: Codable {
    public let ratingKey: String
    // These are omitted by Plex for a freshly-created empty playlist (no items yet), so they must be
    // optional — otherwise the whole playlist fails to decode and silently disappears from the
    // create response and the playlist list.
    public let key: String?
    public let guid: String?
    public let type: String?
    public let title: String
    public let titleSort: String?
    public let summary: String?
    public let viewCount: Int?
    public let lastViewedAt: Int?
    public let duration: Int?
    public let addedAt: Int?
    public let updatedAt: Int?
    public let composite: String?
    public let thumb: String?
    public var leafCount: Int?

    public var sonosID: String?
    public var thumbImageURL: URL?
}
