import SwiftUI

public enum MediaSearchService: String, Sendable, Codable, CaseIterable {
    case apple
    case library
    case plex
    case spotify
    case tidal
    case tuneIn
    case soundcloud

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
        case .tuneIn:
            "TuneIn"
        case .soundcloud:
            "SoundCloud"
        }
    }
    
    public var isBrowseSupported: Bool {
        switch self {
        case .apple:
            true
        case .library:
            true
        case .plex:
            true
        case .spotify:
            true
        case .tidal:
            false
        case .tuneIn:
            false
        case .soundcloud:
            true
        }
    }

    // TODO: Add all icons
    public var icon: some View {
        Image(.tidal)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    @ViewBuilder
    public var image: some View {
        switch self {
        case .apple:
            SwiftUI.Image(systemName: "apple.logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .library:
            SwiftUI.Image(systemName: "books.vertical.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
        default:
            SwiftUI.Image(self.rawValue.capitalized, bundle: .module)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(brandColor.gradient)
        }
    }

    @ViewBuilder
    public var iconForMusicService: some View {
        switch self {
        case .apple:
            Image(systemName: "apple.logo")
                .resizable()
                .scaledToFit()
                .foregroundStyle(brandColor.gradient)
        case .library:
            Image(systemName: "books.vertical.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(brandColor.gradient)
        default:
            SwiftUI.Image(self.rawValue.capitalized, bundle: .module)
                .resizable()
                .scaledToFit()
                .foregroundStyle(brandColor.gradient)
        }
    }
    
    public var brandColor: Color {
        switch self {
        case .apple:
            Color(red: 255.0 / 255.0, green: 78 / 255.0, blue: 107 / 255.0)
        case .spotify:
            Color(red: 30.0 / 255.0, green: 215.0 / 255.0, blue: 96.0 / 255.0)
        case .library:
                .primary
        case .plex:
                .orange
        case .tidal:
                .primary
        case .tuneIn:
                .primary
        case .soundcloud:
            Color(red: 255.0 / 255.0, green: 85.0 / 255.0, blue: 0 / 255.0)
        }
    }
}
