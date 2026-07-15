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
    case deezer
    case sonosRadio
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
        case "deezer":
            self = .deezer
        case "sonosradio":
            self = .sonosRadio
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
        case .deezer:
            "deezer"
        case .sonosRadio:
            "sonosradio"
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
        case .deezer:
            "Deezer"
        case .sonosRadio:
            "Sonos Radio"
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
        case .deezer:
            "deezer"
        case .sonosRadio:
            "sonosradio"
        default:
            ""
        }
    }

    private var librarySymbolName: String {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, watchOS 26.0, *) {
            return "music.pages.fill"
        } else {
            return "books.vertical.fill"
        }
    }
  
    @ViewBuilder
    public var icon: some View {
        switch self {
        case .apple:
            SwiftUI.Image(systemName: "apple.logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .library:
            SwiftUI.Image(systemName: librarySymbolName)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .sonosRadio:
            // Full-colour SONOS badge (original rendering) — no template tint.
            SwiftUI.Image(self.title, bundle: .musicSearchKitBundle)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .tuneIn, .soundcloud, .deezer:
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

    @ViewBuilder
    public var image: some View {
        switch self {
        case .apple:
            SwiftUI.Image(systemName: "apple.logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .library:
            SwiftUI.Image(systemName: librarySymbolName)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .airplay, .unknown:
            EmptyView()
        case .sonosRadio:
            SwiftUI.Image(self.title, bundle: .musicSearchKitBundle)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .tuneIn, .soundcloud, .deezer:
            #if targetEnvironment(macCatalyst)
            let base = UIImage(named: self.title, in: .musicSearchKitBundle, with: nil)!
            let resized = base.resized(to: CGSize(width: 16, height: 16)).withRenderingMode(.alwaysTemplate)
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
            let resized = base.resized(to: CGSize(width: 16, height: 16)).withRenderingMode(.alwaysTemplate)
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
                .foregroundStyle(brandColor.gradient)
#endif
        }
    }
    
    #if canImport(UIKit) && !os(watchOS) && !os(visionOS)
    /// A `UIImage` version of the service logo, for UIKit menus (e.g. the Mac menu bar). Mirrors
    /// the `icon` mapping: SF Symbols for Apple/Library/AirPlay, bundle assets for the rest.
    /// Bundle logos are resized to a menu-glyph size — unlike SF Symbols, UIKit menus render them
    /// at the asset's native (oversized) dimensions otherwise.
    public var uiImage: UIImage? {
        let glyph = CGSize(width: 18, height: 18)
        switch self {
        case .apple:
            return UIImage(systemName: "apple.logo")
        case .library:
            return UIImage(systemName: librarySymbolName)
        case .airplay:
            return UIImage(systemName: "airplayaudio")
        case .tuneIn, .soundcloud, .deezer:
            return UIImage(named: self.title, in: .musicSearchKitBundle, with: nil)?
                .resized(to: glyph).withRenderingMode(.alwaysTemplate)
        case .plex, .tidal, .spotify:
            return UIImage(named: self.sonosRawValue.capitalized, in: .musicSearchKitBundle, with: nil)?
                .resized(to: glyph).withRenderingMode(.alwaysTemplate)
        case .unknown:
            return nil
        }
    }
    #endif

    /// Service supports radio / mix stations from a track or artist.
    public var supportsRadio: Bool {
        switch self {
        case .spotify, .apple, .deezer: true
        default: false
        }
    }

    /// Service supports navigating to artist and album detail screens.
    public var supportsViewArtistAlbum: Bool {
        switch self {
        case .spotify, .apple, .library, .tidal, .plex, .deezer, .soundcloud: true
        default: false
        }
    }

    /// Service supports favoriting / liking individual tracks.
    public var supportsFavoriteTrack: Bool {
        switch self {
        case .spotify, .apple, .soundcloud, .deezer: true
        default: false
        }
    }

    /// Service supports saving / favoriting albums.
    public var supportsFavoriteAlbum: Bool {
        switch self {
        case .spotify, .apple: true
        default: false
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
        case .deezer:
            Color(red: 161.0 / 255.0, green: 0 / 255.0, blue: 255.0 / 255.0)
        case .sonosRadio:
                .primary
        case .unknown:
                .primary
        }
    }
}

extension MusicService {
    public init(from decoder: Decoder) throws {
        struct Key: CodingKey {
            var stringValue: String; var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }
        let container = try decoder.container(keyedBy: Key.self)
        switch container.allKeys.first?.stringValue {
        case "apple":      self = .apple
        case "spotify":    self = .spotify
        case "airplay":    self = .airplay
        case "library":    self = .library
        case "plex":       self = .plex
        case "tidal":      self = .tidal
        case "tuneIn":     self = .tuneIn
        case "soundcloud": self = .soundcloud
        case "deezer":     self = .deezer
        case "sonosRadio": self = .sonosRadio
        default:           self = .unknown
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
