import SwiftUI

public enum MediaSearchService: String, Sendable, Codable {
    case apple
    case library
    case plex
    case spotify
    case tidal

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
        case .tidal:
            "Tidal"
        }
    }

    // TODO: Add all icons
    public var icon: some View {
        Image(.tidal)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}
