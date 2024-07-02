
public enum ContentType: Equatable, Codable, Hashable, Identifiable {
    public var id: String { title }

    case track
    case album
    case artist
    case playlist
    case favorite
    case radio

    case libraryTrack
    case libraryPlaylist
    case libraryAlbum

    public init?(_ type: String) {
        switch type.lowercased() {
        case let str where str.contains("library-songs"):
            self = .libraryTrack
        case let str where str.contains("library-playlist"):
            self = .libraryPlaylist
        case let str where str.contains("library-album"):
            self = .libraryAlbum
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
        case let str where str.contains("favorite"):
            self = .favorite
        default:
            return nil
        }
    }

    public var title: String {
        switch self {
        case .libraryTrack, .track:
            "Song"
        case .libraryPlaylist:
            "My Playlists"
        case .playlist:
            "Playlist"
        case .artist:
            "Artist"
        case .album, .libraryAlbum:
            "Album"
        case .favorite:
            "Favorite"
        case .radio:
            "Radio"
        }
    }
}
