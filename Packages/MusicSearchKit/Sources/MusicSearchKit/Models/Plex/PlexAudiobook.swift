import Foundation

/// A book in a Plex library: an album, as Plex stores it, read with the
/// fields a book needs. Leaner and more forgiving than `PlexAlbumItem` (no
/// required `index`, which books tagged by hand often lack), and carrying
/// what music doesn't use: how many of its files have been played, and its
/// genres, which tell a book kept among music apart.
public struct PlexAudiobookItem: Codable, Sendable {
    public let ratingKey: String
    public let title: String
    public let titleSort: String?
    /// The author: a book's album artist.
    public let parentTitle: String?
    public let parentRatingKey: String?
    public let summary: String?
    public let studio: String?
    public let year: Int?
    public let thumb: String?
    /// The number of files.
    public let leafCount: Int?
    /// How many files have been played to the end.
    public let viewedLeafCount: Int?
    public let lastViewedAt: Int?
    public let addedAt: Int?
    public let librarySectionID: Int?
    public let genres: [PlexTag]?

    /// The token-carrying cover URL, filled in by `PlexAPI`; never stored.
    public var thumbImageURL: URL?
    /// The Sonos-style id (`<server>%3A3%3A<ratingKey>`), as every Plex
    /// item in Cue carries; filled in by `PlexAPI`.
    public var sonosID: String?

    enum CodingKeys: String, CodingKey {
        case ratingKey, title, titleSort, parentTitle, parentRatingKey, summary, studio, year, thumb
        case leafCount, viewedLeafCount, lastViewedAt, addedAt, librarySectionID
        case genres = "Genre"
    }

    /// Whether any of its genres is an audiobook genre.
    public var hasAudiobookGenre: Bool {
        genres?.contains { PlexAudiobookRules.isAudiobookGenre($0.tag) } ?? false
    }
}

/// A tag on a Plex item: a genre, a mood, a collection.
public struct PlexTag: Codable, Sendable, Hashable {
    public let tag: String
}

/// A list of books, one page of it.
public struct PlexAudiobookContainer: Codable, Sendable {
    public let size: Int?
    public let totalSize: Int?
    public let metadata: [PlexAudiobookItem]?

    enum CodingKeys: String, CodingKey {
        case size, totalSize
        case metadata = "Metadata"
    }
}

/// Just the items of a response: a book's files (`/children`), or several
/// items at once (`/library/metadata/a,b,c`), whose container carries none
/// of the fields `PlexLibraryItem` requires.
public struct PlexMetadataList: Codable, Sendable {
    public let metadata: [PlexMetadata]?

    enum CodingKeys: String, CodingKey {
        case metadata = "Metadata"
    }
}

/// A file's metadata read for its chapter marks alone
/// (`/library/metadata/<key>?includeChapters=1`), so nothing else in a
/// track's metadata can fail the decode.
struct PlexChapterLookup: Codable, Sendable {
    let metadata: [Item]?

    struct Item: Codable, Sendable {
        let chapters: [PlexChapter]?

        enum CodingKeys: String, CodingKey {
            case chapters = "Chapter"
        }
    }

    enum CodingKeys: String, CodingKey {
        case metadata = "Metadata"
    }
}

/// A chapter mark inside a file, as Plex reads it from an `.m4b`
/// (`includeChapters=1`). Offsets are milliseconds into the file.
public struct PlexChapter: Codable, Sendable, Hashable {
    public let index: Int?
    public let tag: String?
    public let startTimeOffset: Int?
    public let endTimeOffset: Int?
}

/// A library's genres (`/library/sections/<key>/genre`): each with the key
/// its albums are filtered by.
public struct PlexDirectoryContainer: Codable, Sendable {
    public let directory: [PlexDirectoryItem]?

    enum CodingKeys: String, CodingKey {
        case directory = "Directory"
    }
}

public struct PlexDirectoryItem: Codable, Sendable {
    public let key: String
    public let title: String
}
