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
    case pandora
    case subsonic
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
        case "pandora":
            self = .pandora
        case "subsonic":
            self = .subsonic
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
        case .pandora:
            "pandora"
        case .subsonic:
            "subsonic"
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
        case .pandora:
            "Pandora"
        case .subsonic:
            "Subsonic"
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
        case .pandora:
            "pandora"
        case .subsonic:
            "subsonic"
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
            // The SONOS mark is designed to sit on artwork, so it keeps its
            // original colours. Every other badge here is tinted by the call
            // site (all three are drawn over album art in white).
            SwiftUI.Image(self.title, bundle: .musicSearchKitBundle)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .tuneIn, .soundcloud, .deezer, .pandora:
            SwiftUI.Image(self.title, bundle: .musicSearchKitBundle)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .plex, .tidal, .spotify:
            SwiftUI.Image(self.sonosRawValue.capitalized, bundle: .musicSearchKitBundle)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .subsonic:
            SwiftUI.Image(systemName: "externaldrive.fill.badge.icloud")
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
        case .subsonic:
            SwiftUI.Image(systemName: "externaldrive.fill.badge.icloud")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(brandColor.gradient)
        case .airplay, .unknown:
            EmptyView()
        case .sonosRadio, .pandora:
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
        case .subsonic:
            return UIImage(systemName: "externaldrive.fill.badge.icloud")
        case .tuneIn, .soundcloud, .deezer, .pandora:
            return UIImage(named: self.title, in: .musicSearchKitBundle, with: nil)?
                .resized(to: glyph).withRenderingMode(.alwaysTemplate)
        case .plex, .tidal, .spotify:
            return UIImage(named: self.sonosRawValue.capitalized, in: .musicSearchKitBundle, with: nil)?
                .resized(to: glyph).withRenderingMode(.alwaysTemplate)
        case .sonosRadio:
            return UIImage(named: self.title, in: .musicSearchKitBundle, with: nil)?
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
        case .spotify, .apple, .library, .tidal, .plex, .deezer, .soundcloud, .subsonic: true
        default: false
        }
    }

    /// Service supports favoriting / liking individual tracks.
    /// Plex favorites via its 0–10 track rating (10 = favorite) — see `LikeButtonView`.
    /// Service previews play the full-track stream (it has no short preview
    /// clips), so the preview player streams progressively instead of
    /// downloading first.
    public var streamsFullTrackPreview: Bool {
        switch self {
        case .plex, .subsonic: true
        default: false
        }
    }

    /// The API that builds this service's direct stream URLs, for services
    /// whose tracks Sonos plays as plain HTTP streams. Adding an arm here is
    /// what turns on the direct-HTTP playback mechanism for a service — see
    /// `DirectStreamProvider`.
    public var directStreamProvider: DirectStreamProvider.Type? {
        switch self {
        case .subsonic: SubsonicAPI.self
        default: nil
        }
    }

    /// Service has no Sonos-browsable container URIs — albums, artists and
    /// playlists are expanded into their tracks before queueing (each track
    /// plays as a direct HTTP stream). Pairs with the empty container-URI
    /// cases in `PlayableContent.uri`.
    public var queuesContainersAsTracks: Bool {
        directStreamProvider != nil
    }

    /// Subsonic favorites via star/unstar on the server.
    public var supportsFavoriteTrack: Bool {
        switch self {
        case .spotify, .apple, .soundcloud, .deezer, .plex, .subsonic: true
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

    /// Service ships a recognisable badge, so its stations keep the service
    /// icon on artwork instead of falling back to the generic `radio.fill`
    /// glyph other radio sources use. Independent of how `icon` renders it —
    /// Sonos Radio keeps its original colours, Pandora is tinted like the rest.
    public var hasBrandedRadioBadge: Bool {
        switch self {
        case .sonosRadio, .pandora: true
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
        case .pandora:
            Color(red: 54.0 / 255.0, green: 104.0 / 255.0, blue: 255.0 / 255.0)
        case .subsonic:
            Color(red: 255.0 / 255.0, green: 184.0 / 255.0, blue: 0 / 255.0)
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
        case "pandora":    self = .pandora
        case "subsonic":   self = .subsonic
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
