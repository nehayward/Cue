
public enum ContentType: Equatable, Codable, Hashable, Identifiable {
    public var id: String { title }

    case track
    case album
    case artist
    case playlist
    case favorite
    case radio
    case songRadio
    case artistRadio

    case libraryTrack
    case libraryPlaylist
    case libraryAlbum
    case libraryArtist
    case libraryImportedPlaylists
    case folder

    public init?(_ type: String) {
        switch type.lowercased() {
        case let str where str.contains("library-songs"):
            self = .libraryTrack
        case let str where str.contains("library-playlist-folders"):
            self = .folder
        case let str where str.contains("library-playlist"):
            self = .libraryPlaylist
        case let str where str.contains("library-album"):
            self = .libraryAlbum
        case let str where str.contains("library-artist"):
            self = .libraryArtist
        case let str where str.contains("playlist"):
            self = .playlist
        case let str where str.contains("album"):
            self = .album
        case let str where str.contains("artist"):
            self = .artist
        case let str where str.contains("track"), let str where str.contains("song"), let str where str == "object.item", let str where str == "object.item.audioitem":
            self = .track
        case let str where str.contains("audiobroadcast"), let str where str.contains("radio"), let str where str.contains("station"):
            self = .radio
        case let str where str.contains("favorite"):
            self = .favorite
        case let str where str == "object.container":
            self = .folder
        default:
            return nil
        }
    }

    public var title: String {
        switch self {
        case .libraryTrack:
            "Library Song"
        case .track:
            "Song"
        case .libraryPlaylist:
            "My Playlists"
        case .playlist:
            "Playlist"
        case .artist:
            "Artist"
        case .libraryArtist:
            "Library Artist"
        case .album:
            "Album"
        case .libraryAlbum:
            "Library Album"
        case .favorite:
            "Favorite"
        case .libraryImportedPlaylists:
            "Imported Playlists"
        case .radio, .artistRadio, .songRadio:
            "Radio"
        case .folder:
            "Folder"
        }
    }
    
    public var sonosRawValue: String {
        switch self {
        case .libraryTrack:
            "library-song"
        case .track:
            "song"
        case .libraryPlaylist:
            "library-playlist"
        case .playlist:
            "playlist"
        case .artist:
            "artist"
        case .libraryArtist:
            "library-artist"
        case .album:
            "album"
        case .libraryAlbum:
            "library-album"
        case .favorite:
            "favorite"
        case .libraryImportedPlaylists:
            "library-imported-playlist"
        case .radio, .artistRadio, .songRadio:
            "radio"
        case .folder:
            "folder"
        }
    }
    
    public var symbol: String {
        switch self {
        case .track, .libraryTrack:
            return "music.note"
        case .album, .libraryAlbum:
            return "smallcircle.circle.fill"
        case .artist, .libraryArtist:
            return "music.mic"
        case .playlist, .libraryPlaylist, .libraryImportedPlaylists:
            return "rectangle.stack.badge.play"
        case .radio, .artistRadio, .songRadio:
            return "radio.fill"
        case .favorite:
            return "star.fill"
        case .folder:
            return "folder.fill"
        }
    }
    
    public var isRadio: Bool {
        [.radio, .artistRadio, .songRadio].contains(self)
    }
    
    public var isPlaylist: Bool {
        [.playlist, .libraryImportedPlaylists, .libraryPlaylist].contains(self)
    }
}
