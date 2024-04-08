
public enum MediaKind: String, Equatable, Codable {
    case playlist
    case artist
    case album
    case song
    case favorite

    public init?(_ type: String) {
        switch type.lowercased() {
        case "playlist":
            self =  .playlist
        case "album":
            self = .album
        case "artist":
            self = .artist
        case "track", "song":
            self = .song
        default:
            return nil
        }
    }

    public var title: String {
        switch self {
        case .playlist:
            "Playlist"
        case .artist:
            "Artist"
        case .album:
            "Album"
        case .song:
            "Song"
        case .favorite:
            "Favorite"
        }
    }
}
