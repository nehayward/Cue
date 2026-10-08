import Foundation

/// A page of a music library's collections (`/library/sections/{key}/all?type=18`).
public struct PlexCollectionContainer: Codable {
    public let size: Int?
    /// How many collections the section holds, not just this page.
    public let totalSize: Int?
    public let metadata: [PlexCollection]

    enum CodingKeys: String, CodingKey {
        case size, totalSize
        case metadata = "Metadata"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        totalSize = try container.decodeIfPresent(Int.self, forKey: .totalSize)
        // A library with no collections has no `Metadata` at all.
        metadata = try container.decodeIfPresent([PlexCollection].self, forKey: .metadata) ?? []
    }
}

/// A collection the user has made on their Plex server: a hand-picked (or,
/// for a smart collection, filtered) group of albums — or of artists or
/// songs — kept together the way a folder would keep them.
public struct PlexCollection: Codable, Sendable {
    public let ratingKey: String
    public let key: String?
    public let title: String
    /// What the collection holds: `album`, `artist` or `track`.
    public let subtype: String?
    public let summary: String?
    public let thumb: String?
    /// The mosaic of the collection's covers Plex draws when the collection
    /// has no poster of its own.
    public let composite: String?
    /// How many items the collection holds.
    public let childCount: Int?
    /// A smart collection is a saved filter rather than a list of items, so
    /// there's nothing in it to add, remove or move.
    public let smart: Bool
    /// The order the collection is kept in (see `PlexCollectionSort`). Nil
    /// when Plex didn't say, which is its default: release date.
    public let collectionSort: Int?

    public var sonosID: String?
    public var thumbImageURL: URL?

    enum CodingKeys: String, CodingKey {
        case ratingKey, key, title, subtype, summary, thumb, composite, childCount, smart, collectionSort
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ratingKey = try container.decode(String.self, forKey: .ratingKey)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        title = try container.decode(String.self, forKey: .title)
        subtype = try container.decodeIfPresent(String.self, forKey: .subtype)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        thumb = try container.decodeIfPresent(String.self, forKey: .thumb)
        composite = try container.decodeIfPresent(String.self, forKey: .composite)
        // Plex sends a collection's numbers as strings ("12") where every
        // other count in its JSON is a number, so take either.
        childCount = container.decodeLenientInt(forKey: .childCount)
        collectionSort = container.decodeLenientInt(forKey: .collectionSort)
        smart = container.decodeLenientBool(forKey: .smart) ?? false
    }

    /// Whether the collection is kept in an order of its own, the only order
    /// its items can be moved in.
    public var isCustomSorted: Bool {
        collectionSort == PlexCollectionSort.custom.rawValue
    }

    /// The order the collection is kept in; Release Date, Plex's default,
    /// when Plex didn't say.
    public var sortOrder: PlexCollectionSort {
        collectionSort.flatMap { PlexCollectionSort(rawValue: $0) } ?? .releaseDate
    }

    /// "12 albums", "1 artist", "30 songs": what the collection holds and
    /// how many. Nil when Plex didn't say.
    public var itemCountLabel: String? {
        guard let childCount else { return nil }
        let noun: (one: String, other: String) = switch subtype {
        case "album": ("album", "albums")
        case "artist": ("artist", "artists")
        case "track": ("song", "songs")
        default: ("item", "items")
        }
        return childCount == 1 ? "1 \(noun.one)" : "\(childCount.formatted()) \(noun.other)"
    }
}

/// The orders Plex can keep a collection in (`collectionSort`).
public enum PlexCollectionSort: Int, Sendable {
    case releaseDate = 0
    case alphabetical = 1
    case custom = 2
}

public extension Array where Element == PlexMetadata {
    /// A collection's items in `sort`'s order.
    ///
    /// The server hands a collection's items back in the order they were
    /// placed, whatever the collection's sort, so Release Date and
    /// Alphabetical are put in order here, as Plex's own apps do: Release
    /// Date oldest first by original release date (else year, undated
    /// last), Alphabetical by sort title, which drops a leading article.
    /// Custom is the order they came in. Ties go by sort title.
    func inCollectionOrder(_ sort: PlexCollectionSort) -> [PlexMetadata] {
        func titleOrder(_ lhs: PlexMetadata, _ rhs: PlexMetadata) -> Bool {
            (lhs.titleSort ?? lhs.title).localizedStandardCompare(rhs.titleSort ?? rhs.title) == .orderedAscending
        }
        switch sort {
        case .custom:
            return self
        case .alphabetical:
            return sorted(by: titleOrder)
        case .releaseDate:
            return sorted { lhs, rhs in
                switch (lhs.releaseKey, rhs.releaseKey) {
                case let (left?, right?) where left != right:
                    return left < right
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                default:
                    return titleOrder(lhs, rhs)
                }
            }
        }
    }
}

private extension PlexMetadata {
    /// "1977-12-12", or "1977" from the year alone: either compares in date
    /// order as text.
    var releaseKey: String? {
        originallyAvailableAt ?? year.map { String(format: "%04d", $0) }
    }
}

private extension KeyedDecodingContainer {
    /// A number Plex may send as a number or as a string.
    func decodeLenientInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        return (try? decodeIfPresent(String.self, forKey: key)).flatMap(Int.init)
    }

    /// A flag Plex may send as a boolean, a number or a string ("1").
    func decodeLenientBool(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        return decodeLenientInt(forKey: key).map { $0 != 0 }
            ?? (try? decodeIfPresent(String.self, forKey: key)).map { $0.lowercased() == "true" }
    }
}

/// A page of what a collection holds (`/library/collections/{key}/children`).
public struct PlexCollectionItemsContainer: Codable {
    public let size: Int?
    /// How many items the collection holds, not just this page.
    public let totalSize: Int?
    public let metadata: [PlexMetadata]

    enum CodingKeys: String, CodingKey {
        case size, totalSize
        case metadata = "Metadata"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        totalSize = try container.decodeIfPresent(Int.self, forKey: .totalSize)
        // One item that doesn't decode drops on its own rather than taking
        // the whole collection with it.
        metadata = (try container.decodeIfPresent([LossyItem].self, forKey: .metadata) ?? []).compactMap(\.value)
    }

    private struct LossyItem: Decodable {
        let value: PlexMetadata?

        init(from decoder: Decoder) throws {
            value = try? PlexMetadata(from: decoder)
        }
    }
}
