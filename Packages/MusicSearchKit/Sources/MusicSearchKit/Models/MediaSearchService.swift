import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum MediaSearchService: String, Sendable, Codable, CaseIterable {
    case apple
    case library
    case plex
    case spotify
    case tidal
    case tuneIn
    case soundcloud
    case deezer
    case sonosRadio
    case pandora
    case subsonic
    /// Audio files in a folder the user picked — on this device or in
    /// iCloud Drive. Indexed and played by the app itself; there is no
    /// account and no server.
    case files

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
        case .deezer:
            "Deezer"
        case .sonosRadio:
            "Sonos Radio"
        case .pandora:
            "Pandora"
        case .subsonic:
            "Subsonic"
        case .files:
            "Files"
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
        case .deezer:
            true
        case .sonosRadio:
            true
        case .pandora:
            true
        case .subsonic:
            true
        case .files:
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
    
    private var librarySymbolName: String {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, watchOS 26.0, *) {
            return "music.pages.fill"
        } else {
            return "books.vertical.fill"
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
            // SF Symbol, not a bundle asset — Subsonic-compatible servers
            // (Navidrome, Airsonic, …) don't share one brand mark.
            SwiftUI.Image(systemName: "externaldrive.fill.badge.icloud")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(brandColor.gradient)
        case .files:
            SwiftUI.Image(systemName: "folder.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(brandColor.gradient)
        case .sonosRadio, .pandora:
            // These assets are full-colour badges (original rendering); don't
            // template-tint them or the artwork collapses into a solid blob.
            #if targetEnvironment(macCatalyst)
            // Catalyst renders unrasterized asset images at full size inside menus,
            // so pre-rasterize to a small badge while keeping the original colours.
            let base = UIImage(named: self.title, in: .module, with: nil)!
            let resized = base.resized(to: CGSize(width: 16, height: 16))

            SwiftUI.Image(uiImage: resized)
                .renderingMode(.original)
                .resizable()
                .aspectRatio(contentMode: .fit)
            #else
            SwiftUI.Image(self.title, bundle: .module)
                .resizable()
                .aspectRatio(contentMode: .fit)
            #endif
        case .tuneIn, .soundcloud, .deezer:
            #if targetEnvironment(macCatalyst)
            let base = UIImage(named: self.title, in: .module, with: nil)!
            let templated = base.withRenderingMode(.alwaysTemplate)
            let resized = templated.resized(to: CGSize(width: 16, height: 16)).withTintColor(.label)

            SwiftUI.Image(uiImage: resized)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(brandColor.gradient)
            #else
            SwiftUI.Image(self.title, bundle: .module)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(brandColor.gradient)
            #endif
        default:
            #if targetEnvironment(macCatalyst)
            let base = UIImage(named: self.rawValue.capitalized, in: .module, with: nil)!
            let templated = base.withRenderingMode(.alwaysTemplate)
            let resized = templated.resized(to: CGSize(width: 16, height: 16)).withTintColor(.label)

            SwiftUI.Image(uiImage: resized)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(brandColor.gradient)
            #else
            SwiftUI.Image(self.rawValue.capitalized, bundle: .module)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(brandColor.gradient)
            #endif
        }
    }

    @ViewBuilder
    public var iconForMusicService: some View {
        switch self {
        case .apple:
            Image(systemName: "apple.logo")
                .foregroundStyle(brandColor.gradient)
        case .library:
            Image(systemName: librarySymbolName)
                .resizable()
                .scaledToFit()
                .foregroundStyle(brandColor.gradient)
        case .subsonic:
            Image(systemName: "externaldrive.fill.badge.icloud")
                .resizable()
                .scaledToFit()
                .foregroundStyle(brandColor.gradient)
        case .files:
            Image(systemName: "folder.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(brandColor.gradient)
        case .sonosRadio, .pandora:
#if targetEnvironment(macCatalyst)
            // Catalyst renders unrasterized asset images at full size inside menus,
            // so pre-rasterize to a small badge while keeping the original colours.
            let base = UIImage(named: self.title, in: .module, with: nil)!
            let resized = base.resized(to: CGSize(width: 16, height: 16))

            SwiftUI.Image(uiImage: resized)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
#else
            SwiftUI.Image(self.title, bundle: .module)
                .resizable()
                .scaledToFit()
#endif
        case .tuneIn, .soundcloud, .deezer:
#if targetEnvironment(macCatalyst)
            let base = UIImage(named: self.title, in: .module, with: nil)!
            let templated = base.withRenderingMode(.alwaysTemplate)
            let resized = templated.resized(to: CGSize(width: 16, height: 16)).withTintColor(.label)

            SwiftUI.Image(uiImage: resized)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(brandColor.gradient)
#else
            SwiftUI.Image(self.title, bundle: .module)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(brandColor.gradient)
#endif
        default:
#if targetEnvironment(macCatalyst)
            let base = UIImage(named: self.rawValue.capitalized, in: .module, with: nil)!
            let templated = base.withRenderingMode(.alwaysTemplate)
            let resized = templated.resized(to: CGSize(width: 16, height: 16)).withTintColor(.label)
            
            SwiftUI.Image(uiImage: resized)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(brandColor.gradient)
#else
            SwiftUI.Image(self.rawValue.capitalized, bundle: .module)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(brandColor.gradient)
#endif
        }
    }
    
    /// The brand mark as a bare `Image`, for places that only take one — a
    /// `Tab`'s label, whose bar extracts the image and ignores any view
    /// wrapped around it. `image` and `iconForMusicService` are sized and
    /// tinted views; this is the same asset before any of that.
    public var tabImage: Image {
        switch self {
        case .apple:
            Image(systemName: "apple.logo")
        case .library:
            Image(systemName: librarySymbolName)
        case .subsonic:
            Image(systemName: "externaldrive.fill.badge.icloud")
        case .files:
            Image(systemName: "folder.fill")
        case .sonosRadio, .pandora:
            // Full-colour badges: left in their original rendering, as
            // `image` does, so they don't collapse into a solid blob.
            Self.tabSized(named: self.title, template: false)
        case .tuneIn, .soundcloud, .deezer:
            Self.tabSized(named: self.title, template: true)
        default:
            Self.tabSized(named: self.rawValue.capitalized, template: true)
        }
    }

    /// The brand mark in its brand colour, baked into the image, for a
    /// `Menu` row. A menu is a UIKit menu underneath: it takes the row's
    /// image and throws away any `foregroundStyle` or `tint` around it,
    /// drawing a template image in the menu's own tint. Only an image
    /// rendered as original keeps its colour — so this tints the symbol or
    /// asset up front, flat (no gradient) since a UIImage can't carry one.
    public var menuImage: Image {
        #if canImport(UIKit) && !os(watchOS) && !os(visionOS)
        // `.label` outright for the marks whose brand colour is `.primary`:
        // that stays dynamic where a converted Color might not.
        let tint: UIColor = brandColor == .primary ? .label : UIColor(brandColor)
        switch self {
        case .apple, .library, .subsonic, .files:
            let name = switch self {
            case .apple: "apple.logo"
            case .library: librarySymbolName
            case .subsonic: "externaldrive.fill.badge.icloud"
            default: "folder.fill"
            }
            if let symbol = UIImage(systemName: name) {
                return Image(uiImage: symbol.withTintColor(tint, renderingMode: .alwaysOriginal))
            }
            return Image(systemName: name)
        case .sonosRadio, .pandora:
            // Full-colour badges: already their own colours.
            return Self.tabSized(named: self.title, template: false)
        case .tuneIn, .soundcloud, .deezer:
            return Self.menuTinted(named: self.title, tint: tint)
        default:
            return Self.menuTinted(named: self.rawValue.capitalized, tint: tint)
        }
        #else
        return tabImage
        #endif
    }

    #if canImport(UIKit) && !os(watchOS) && !os(visionOS)
    /// A bundle asset at menu size, tinted and rendered as original so the
    /// menu leaves the colour alone.
    private static func menuTinted(named name: String, tint: UIColor) -> Image {
        guard let base = UIImage(named: name, in: .module, with: nil) else {
            return Image(name, bundle: .module).renderingMode(.template)
        }
        let resized = base.withRenderingMode(.alwaysTemplate).resized(to: CGSize(width: 24, height: 24))
        return Image(uiImage: resized.withTintColor(tint, renderingMode: .alwaysOriginal))
    }
    #endif

    /// A bundle asset at tab-icon size. The tab bar scales what it draws
    /// itself, but the More list on iPhone draws the image as it comes —
    /// and the brand assets come large.
    private static func tabSized(named name: String, template: Bool) -> Image {
        #if canImport(UIKit) && !os(watchOS) && !os(visionOS)
        if let base = UIImage(named: name, in: .module, with: nil) {
            let resized = base.resized(to: CGSize(width: 24, height: 24))
            return Image(uiImage: template ? resized.withRenderingMode(.alwaysTemplate) : resized)
        }
        #endif
        let image = Image(name, bundle: .module)
        return template ? image.renderingMode(.template) : image
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
        case .deezer:
            Color(red: 161.0 / 255.0, green: 0 / 255.0, blue: 255.0 / 255.0)
        case .sonosRadio:
                .primary
        case .pandora:
            Color(red: 54.0 / 255.0, green: 104.0 / 255.0, blue: 255.0 / 255.0)
        case .subsonic:
            Color(red: 255.0 / 255.0, green: 184.0 / 255.0, blue: 0 / 255.0)
        case .files:
            // The Files app's folder blue.
            Color(red: 50.0 / 255.0, green: 150.0 / 255.0, blue: 255.0 / 255.0)
        }
    }
}


#if canImport(UIKit) && !os(watchOS) && !os(visionOS)
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
