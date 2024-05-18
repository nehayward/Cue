
public enum MediaSearchService: String, Sendable, Codable {
    case apple
    case spotify
    case library
    case plex

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

    public var title: String {
        switch self {
        case .apple:
            "Apple Music"
        case .spotify:
            "Spotify"
        case .library:
            "Library"
        case .plex:
            "Plex"
        }
    }
}
