import Foundation

/// How a list of Subsonic albums is ordered. Unlike songs, albums *are*
/// sorted by the server: each case is one of `getAlbumList2`'s list types.
public enum SubsonicAlbumSort: String, CaseIterable, Sendable, Identifiable {
    case title
    case artist
    case recentlyAdded
    case mostPlayed
    case recentlyPlayed

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .recentlyAdded: "Recently Added"
        case .mostPlayed: "Most Played"
        case .recentlyPlayed: "Recently Played"
        }
    }

    /// `getAlbumList2`'s `type` parameter.
    public var apiType: String {
        switch self {
        case .title: "alphabeticalByName"
        case .artist: "alphabeticalByArtist"
        case .recentlyAdded: "newest"
        case .mostPlayed: "frequent"
        case .recentlyPlayed: "recent"
        }
    }
}
