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
        case .tuneIn:
            "TuneIn"
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
            case .library:
                SwiftUI.Image(systemName: "books.vertical.fill")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .tuneIn, .soundcloud:
                SwiftUI.Image(self.title, bundle: .musicSearchKitBundle)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .plex, .tidal, .spotify:
                SwiftUI.Image(self.sonosRawValue.capitalized, bundle: .musicSearchKitBundle)
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
        case .library:
            SwiftUI.Image(systemName: "books.vertical.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .airplay, .unknown:
            EmptyView()
        case .tuneIn, .soundcloud:
            #if targetEnvironment(macCatalyst)
            let base = UIImage(named: self.title, in: .musicSearchKitBundle, with: nil)!
            let templated = base.withRenderingMode(.alwaysTemplate)
            let resized = templated.resized(to: CGSize(width: 16, height: 16)).withTintColor(.label)
            
            SwiftUI.Image(uiImage: resized)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(brandColor.gradient)
            #else
            SwiftUI.Image(self.title, bundle: .musicSearchKitBundle)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(brandColor.gradient)
            #endif
        case .plex, .tidal, .spotify:
#if targetEnvironment(macCatalyst)
            let base = UIImage(named: self.sonosRawValue.capitalized, in: .musicSearchKitBundle, with: nil)!
            let templated = base.withRenderingMode(.alwaysTemplate)
            let resized = templated.resized(to: CGSize(width: 16, height: 16)).withTintColor(.label)
            SwiftUI.Image(uiImage: resized)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(brandColor.gradient)
#else
            SwiftUI.Image(self.sonosRawValue.capitalized, bundle: .musicSearchKitBundle)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(brandColor)
                .tint(brandColor)
#endif
        }
    }
    
    public var brandColor: Color {
        switch self {
        case .apple:
            Color(red: 255.0 / 255.0, green: 78 / 255.0, blue: 107 / 255.0)
        case .spotify:
            Color(red: 30.0 / 255.0, green: 215.0 / 255.0, blue: 96.0 / 255.0)
        case .airplay:
                .white
        case .library:
                .white
        case .plex:
                .orange
        case .tidal:
                .primary
        case .tuneIn:
                .primary
        case .soundcloud:
            Color(red: 255.0 / 255.0, green: 85.0 / 255.0, blue: 0 / 255.0)
        case .unknown:
                .primary
        }
    }
}

#if canImport(UIKit) && !os(watchOS) && !os(visionOS)
import UIKit

extension UIImage {
    func resized(to size: CGSize, scale: CGFloat = UIScreen.main.scale) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
#endif
