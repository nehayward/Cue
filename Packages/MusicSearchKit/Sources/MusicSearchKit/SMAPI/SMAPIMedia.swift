import Foundation

/// A single item returned by a SMAPI `getMetadata` / `search` response. Covers
/// both `mediaCollection` (containers like search categories, stations lists)
/// and `mediaMetadata` (playable items like streams, programs, tracks).
public struct SMAPIMediaItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let itemType: String
    public let title: String
    public let summary: String?
    public let artist: String?
    public let album: String?
    public let albumArtURI: String?
    public let mimeType: String?
    /// True for `mediaCollection` entries (containers you browse into).
    public let isContainer: Bool
    public let canPlay: Bool
    public let canEnumerate: Bool

    public init(
        id: String,
        itemType: String,
        title: String,
        summary: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        albumArtURI: String? = nil,
        mimeType: String? = nil,
        isContainer: Bool,
        canPlay: Bool,
        canEnumerate: Bool
    ) {
        self.id = id
        self.itemType = itemType
        self.title = title
        self.summary = summary
        self.artist = artist
        self.album = album
        self.albumArtURI = albumArtURI
        self.mimeType = mimeType
        self.isContainer = isContainer
        self.canPlay = canPlay
        self.canEnumerate = canEnumerate
    }
}

/// The decoded body of a SMAPI `getMetadataResult` / `searchResult`.
public struct SMAPIMediaResult: Sendable {
    public let index: Int
    public let count: Int
    public let total: Int
    public let items: [SMAPIMediaItem]

    public init(index: Int, count: Int, total: Int, items: [SMAPIMediaItem]) {
        self.index = index
        self.count = count
        self.total = total
        self.items = items
    }

    public var hasMore: Bool { index + items.count < total }
    public var nextIndex: Int { index + items.count }
}
