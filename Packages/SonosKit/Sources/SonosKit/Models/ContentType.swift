
public enum ContentType: Equatable, Codable, Hashable, Identifiable {
    public var id: String { title }

    case track
    case album
    case artist
    case playlist
    case favorite
    case radio

    case libraryTrack
    case userPlaylist

    public init?(_ type: String) {
        switch type.lowercased() {
        case let str where str.contains("playlist"):
            self = .playlist
        case let str where str.contains("album"):
            self = .album
        case let str where str.contains("artist"):
            self = .artist
        case let str where str.contains("track"), let str where str.contains("song"), let str where str == "object.item", let str where str == "object.item.audioitem":
            self = .track
        case let str where str.contains("audiobroadcast"), let str where str.contains("radio"):
            self = .radio
        default:
            return nil
        }
    }

    public var title: String {
        switch self {
        case .libraryTrack:
            "Song"
        case .userPlaylist:
            "My Playlists"
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
        case .radio:
            "Radio"
        }
    }
}
