import Foundation

public enum PlaybackService: Sendable, Hashable, Equatable {
    case tv
    case queue
    case radio
    case lineIn
    case spotifyConnect
    case airplay
    case unknown

    public var title: String {
        switch self {
        case .tv:
            "TV"
        case .radio:
            "Radio"
        case .lineIn:
            "Line In"
        case .spotifyConnect:
            "Spotify Connect"
        case .airplay:
            "Airplay"
        case .unknown:
            "Unknown"
        case .queue:
            "Queue"
        }
    }
}
