
public enum ContentType: Equatable {
    case playlist
    case artist
    case album
    case track

    init?(_ type: String) {
        switch type.lowercased() {
        case "playlist":
            self =  .playlist
        case "album":
            self = .album
        case "artist":
            self = .artist
        case "track", "song":
            self = .track
        default:
            return nil
        }
    }
}
