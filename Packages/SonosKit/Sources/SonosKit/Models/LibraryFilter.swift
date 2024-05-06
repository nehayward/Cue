
enum LibraryFilter {
    case artist
    case album
    case track

    var id: String {
        switch self {
        case .artist:
            return "A:ALBUMARTIST"
        case .album:
            return "A:ALBUM"
        case .track:
            return "A:TRACKS"
        }
    }
}
