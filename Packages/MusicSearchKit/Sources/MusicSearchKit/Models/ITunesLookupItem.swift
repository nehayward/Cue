import Foundation

/// Generic decoded row from `https://itunes.apple.com/lookup?id=...`.
/// Unlike `ItunesResult`, this preserves fields across all `wrapperType` values
/// (track, collection, artist), so callers can resolve any kind of Apple Music URL.
public struct ITunesLookupItem: Decodable, Sendable, Equatable {
    public let wrapperType: String?
    public let kind: String?
    public let trackName: String?
    public let collectionName: String?
    public let artistName: String?
    public let collectionArtistName: String?
    public let primaryGenreName: String?
    public let artworkUrl60: String?
    public let artworkUrl100: String?
    public let trackId: Int?
    public let collectionId: Int?
    public let artistId: Int?

    public var thumbnailURL: URL? {
        artworkUrl100.flatMap(URL.init(string:))
    }

    public func artworkURL(size: Int) -> URL? {
        guard let raw = artworkUrl100 else { return nil }
        let scaled = raw.replacingOccurrences(of: "100x100bb", with: "\(size)x\(size)cc")
        return URL(string: scaled)
    }

    public var resolvedArtistName: String? {
        artistName ?? collectionArtistName
    }

    public var displayTitle: String {
        switch wrapperType {
        case "artist": return artistName ?? ""
        case "collection": return collectionName ?? ""
        default: return trackName ?? collectionName ?? artistName ?? ""
        }
    }

    public var displaySubtitle: String {
        switch wrapperType {
        case "artist": return primaryGenreName ?? "Artist"
        case "collection": return resolvedArtistName ?? ""
        default: return resolvedArtistName ?? ""
        }
    }
}

public struct ITunesLookupResponse: Decodable, Sendable {
    public let resultCount: Int
    public let results: [ITunesLookupItem]
}
