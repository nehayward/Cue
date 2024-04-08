
public enum MusicService: Sendable, Codable {
    case apple
    case spotify
    case airplay
    case unknown

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
}
