
public enum MediaSearchService: String, Sendable, Codable {
    case apple
    case spotify

    public init?(service: String) {
        switch service {
        case "spotify":
            self = .spotify
        case "apple":
            self = .apple
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
        }
    }
}
