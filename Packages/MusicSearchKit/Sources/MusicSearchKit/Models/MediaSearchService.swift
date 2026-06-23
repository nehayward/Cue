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
                .resizable()
                .scaledToFit()
                .foregroundStyle(brandColor.gradient)
        case .library:
            Image(systemName: librarySymbolName)
                .resizable()
                .scaledToFit()
                .foregroundStyle(brandColor.gradient)
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
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(brandColor.gradient)
#endif
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
        case .deezer:
            Color(red: 161.0 / 255.0, green: 0 / 255.0, blue: 255.0 / 255.0)
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
