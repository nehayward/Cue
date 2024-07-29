import SwiftUI

public enum MediaSearchService: String, Sendable, Codable, CaseIterable {
    case apple
    case library
    case plex
    case spotify
    case tidal
    case tuneIn

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
        case .spotify:
            SwiftUI.Image(.spotify)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .library:
            SwiftUI.Image(systemName: "books.vertical.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .plex:
            SwiftUI.Image(.plex)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .tidal:
            SwiftUI.Image(.tidal)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .tuneIn:
            SwiftUI.Image(.tuneIn)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.foreground)
        }
    }

    @ViewBuilder
    public var iconForMusicService: some View {
        switch self {
        case .apple:
            Image(systemName: "apple.logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.foreground)
        case .spotify:
            SwiftUI.Image(.spotify)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .library:
            Image(systemName: "books.vertical.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.foreground)
        case .plex:
            SwiftUI.Image(.plex)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.orange.gradient)
        case .tidal:
            SwiftUI.Image(.tidal)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.foreground)
        case .tuneIn:
            MediaSearchService.tuneIn.image
        }
    }
}
