import SwiftUI
import MusicSearchKit

public enum MusicService: Sendable, Codable, CaseIterable {
    case apple
    case spotify
    case airplay
    case library
    case plex
    case tidal
    case tuneIn
    case soundcloud
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
        case "soundcloud":
            self = .soundcloud
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
        case .soundcloud:
            "soundcloud"
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
        case .soundcloud:
            "SoundCloud"
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
        case .soundcloud:
            "soundcloud"
        default:
            ""
        }
    }


    @ViewBuilder
    public var icon: some View {
        VStack {
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
            case .soundcloud:
                SwiftUI.Image(self.sonosRawValue, bundle: .musicSearchKitBundle)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .onAppear {
                        let musicSearchBundle = Bundle.musicSearchKitBundle
                        print(musicSearchBundle)
                       
                    }
            case .airplay:
                SwiftUI.Image(systemName: "airplayaudio")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .unknown:
                EmptyView()
            }
        }
        #if !os(watchOS) && !os(tvOS)
        .foregroundStyle(.bar)
        #else
        .foregroundStyle(.white.gradient)
        #endif
        .shadow(radius: 1)
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
        default:
            SwiftUI.Image(self.sonosRawValue, bundle: .musicSearchKitBundle)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
    
    public var brandColor: Color {
        switch self {
        case .apple:
                .red
        case .spotify:
            Color(red: 30.0 / 255.0, green: 215.0 / 255.0, blue: 96.0 / 255.0)
        case .airplay:
                .white
        case .library:
                .white
        case .plex:
                .orange
        case .tidal:
                .teal
        case .tuneIn:
                .white
        case .soundcloud:
                .black
        case .unknown:
                .primary
        }
    }
}
