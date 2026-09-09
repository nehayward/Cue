import Foundation

/// How a list of Subsonic albums is ordered. Unlike songs, albums *are*
/// sorted by the server: each case is one of `getAlbumList2`'s list types.
///
/// The server's `frequent` and `recent` lists are deliberately not here.
/// They rank albums by the plays clients have scrobbled to the server, and
/// Cue streams without scrobbling, so on a server only Cue plays from they
/// are empty — a sort that shows nothing.
public enum SubsonicAlbumSort: String, CaseIterable, Sendable, Identifiable {
    case title
    case artist
    case recentlyAdded

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .recentlyAdded: "Recently Added"
        }
    }

    /// `getAlbumList2`'s `type` parameter.
    public var apiType: String {
        switch self {
        case .title: "alphabeticalByName"
        case .artist: "alphabeticalByArtist"
        case .recentlyAdded: "newest"
        }
    }
}
