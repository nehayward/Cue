import SwiftUI

public enum SonosMusicServiceType: Equatable, Hashable, Codable, CaseIterable {
    case apple
    case spotify
    case airplay
    case library
    case plex
    case tidal
    case tuneIn
    case unknown

    public init?(service: String) {
        switch service {
        case "spotify":
            self = .spotify
        case "apple", "music":
            self = .apple
        case "library":
            self = .library
        case "plex":
            self = .plex
        case "tidal":
            self = .tidal
        case "tunein":
            self = .tuneIn
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
        case .tidal:
            "tidal"
        case .tuneIn:
            "tunein"
        default:
            nil
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
        case .tidal:
            "Tidal"
        default:
            ""
        }
    }
    
    public var sonosRawValue: String {
        switch self {
        case .apple:
            "apple"
        case .spotify:
            "spotify"
        case .library:
            "library"
        case .plex:
            "plex"
        case .tidal:
            "tidal"
        case .tuneIn:
            "tunein"
        default:
            ""
        }
    }


    @ViewBuilder
    public var icon: some View {
        Group {
            switch self {
            case .apple:
                SwiftUI.Image(systemName: "apple.logo")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .spotify:
                SwiftUI.Image(.spotify)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .library:
                SwiftUI.Image(systemName: "books.vertical.fill")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .plex:
                SwiftUI.Image(.plex)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .tidal:
                SwiftUI.Image(.tidal)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .tuneIn:
                SwiftUI.Image(.tuneIn)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .airplay:
                SwiftUI.Image(systemName: "airplayaudio")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .unknown:
                EmptyView()
            }
        }
        #if !os(watchOS)
        .foregroundStyle(.bar)
        #else
        .foregroundStyle(.white.gradient)
        #endif
        .shadow(radius: 8)
        .environment(\.colorScheme, .light)
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
        case .airplay, .unknown:
            EmptyView()
        case .tidal:
            SwiftUI.Image(.tidal)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .tuneIn:
            SwiftUI.Image(.tuneIn)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}
