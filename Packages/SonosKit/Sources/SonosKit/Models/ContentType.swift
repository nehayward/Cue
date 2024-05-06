
public enum ContentType: Equatable, Codable {
    case playlist
    case artist
    case album
    case track
    case favorite

    public init?(_ type: String) {
        switch type.lowercased() {
        case let str where str.contains("playlist"):
            self = .playlist
        case let str where str.contains("album"):
            self = .album
        case let str where str.contains("artist"):
            self = .artist
        case let str where str.contains("track"), let str where str.contains("song"):
            self = .track
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
        case .track:
            "Song"
        case .favorite:
            "Favorite"
        }
    }
}
