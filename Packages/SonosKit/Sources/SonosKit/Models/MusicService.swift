
public enum MusicService: Sendable, Codable {
    case apple
    case spotify
    case airplay
    case library
    case unknown

    public init?(service: String) {
        switch service {
        case "spotify":
            self = .spotify
        case "apple":
            self = .apple
        case "library":
            self = .library
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
        default:
            nil
        }
    }
}
