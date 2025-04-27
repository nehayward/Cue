
enum LibraryFilter {
    case artist
    case album
    case track
    case playlist
    case importedPlaylists

    var id: String {
        switch self {
        case .artist:
            return "A:ALBUMARTIST"
        case .album:
            return "A:ALBUM"
        case .track:
            return "A:TRACKS"
        case .playlist:
            return "A:PLAYLISTS"
        case .importedPlaylists:
            return "A:PLAYLISTS:"
        }
    }
}
