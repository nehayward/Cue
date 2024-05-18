
public enum MusicService: Sendable, Codable {
    case apple
    case spotify
    case airplay
    case library
    case plex
    case unknown

    public init?(service: String) {
        switch service {
        case "spotify":
            self = .spotify
        case "apple":
            self = .apple
        case "library":
            self = .library
        case "plex":
            self = .plex
        default:
            return nil
        }
    }

    var name: String? {
        switch self {
        case .apple:
            "apple"
        case .spotify:
            "spotify"
        case .library:
            "library"
        case .plex:
            "plex"
        default:
            nil
        }
    }
}
