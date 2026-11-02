import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Ported from Clic (`ServiceAvatarStack` in its MusicSearchKit), for Cue's
// services: Audiobookshelf and Files have chips of their own, and TuneIn's
// mark is a white glyph on its disc, as Cue tints it everywhere else.

// MARK: - Avatar chip

/// A service drawn as a small circular chip: a brand-coloured disc with the
/// service's mark on top.
///
/// The raw service artwork is wildly inconsistent — SF Symbols, template
/// glyphs, full-colour badges — so a row of it reads as a jumble of
/// mismatched shapes and weights. Wrapping every service in the same disc
/// gives the row one silhouette and lets brand colour, rather than artwork
/// size, do the identifying.
public struct ServiceAvatar: View {
    private let service: MediaSearchService
    private let size: CGFloat

    public init(service: MediaSearchService, size: CGFloat = 20) {
        self.service = service
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(service.avatarFill.gradient)
            .overlay { mark }
            .overlay {
                // Hairline so the darkest chips (Tidal, Sonos Radio) don't
                // melt into a dark background.
                Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .frame(width: size, height: size)
    }

    /// Marks sit centred, so they have to fit inside what the neighbour's
    /// cutout leaves behind — see `ServiceAvatarStack.overlap`. Artwork runs a
    /// little larger than a glyph because it carries its own padding.
    static let glyphScale: CGFloat = 0.54
    static let artworkScale: CGFloat = 0.6

    @ViewBuilder
    private var mark: some View {
        switch service.avatarStyle {
        case .glyph:
            let glyphSize = size * Self.glyphScale
            service.avatarGlyph(size: glyphSize)
                .foregroundStyle(.white)
                .frame(width: glyphSize, height: glyphSize)
        case .artwork:
            let artworkSize = size * Self.artworkScale
            service.avatarArtwork(size: artworkSize)
                .frame(width: artworkSize, height: artworkSize)
        }
    }
}

// MARK: - Avatar stack

/// Overlapping service chips, the way stacked contact avatars read.
///
/// Each chip knocks a hole out of itself where its neighbour sits, so the gap
/// between circles is transparent rather than painted — the separation holds
/// up on any background, glass included, in either colour scheme.
public struct ServiceAvatarStack: View {
    private let services: [MediaSearchService]
    private let maxVisible: Int?
    private let size: CGFloat
    private let overlap: CGFloat
    private let ringWidth: CGFloat

    @Environment(\.layoutDirection) private var layoutDirection

    /// - Parameters:
    ///   - services: Chips, drawn leading to trailing.
    ///   - maxVisible: Cap on the chips drawn; the rest collapse into a
    ///     trailing `+n`. `nil` draws them all.
    ///   - size: Diameter of a single chip.
    ///   - overlap: Fraction of a chip covered by the next one, 0...1. Keep it
    ///     low: past roughly 0.15 the cutout takes the edge off the marks.
    ///   - ringWidth: Width of the transparent gap knocked out between chips.
    public init(
        services: [MediaSearchService],
        maxVisible: Int? = nil,
        size: CGFloat = 20,
        overlap: CGFloat = 0.13,
        ringWidth: CGFloat = 1.25
    ) {
        self.services = services
        self.maxVisible = maxVisible
        self.size = size
        self.overlap = overlap
        self.ringWidth = ringWidth
    }

    /// The chips that actually get drawn. One slot goes to the `+n` counter, so
    /// capping at `n` never trades a chip for a counter that says `+1`.
    private var visible: [MediaSearchService] {
        guard let maxVisible, services.count > maxVisible else { return services }
        return Array(services.prefix(max(0, maxVisible - 1)))
    }

    private var overflow: Int { services.count - visible.count }

    public var body: some View {
        HStack(spacing: -size * overlap) {
            ForEach(Array(visible.enumerated()), id: \.element) { index, service in
                chip(ServiceAvatar(service: service, size: size),
                     isLast: overflow == 0 && index == visible.count - 1)
            }

            if overflow > 0 {
                chip(OverflowAvatar(count: overflow, size: size), isLast: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(services.map(\.title).joined(separator: ", ")))
    }

    /// A chip is drawn under the one that follows it, so it is the one that
    /// gets cut. The last chip has nothing over it and stays whole.
    private func chip(_ avatar: some View, isLast: Bool) -> some View {
        avatar.mask {
            NeighbourCutout(
                neighbourOffset: isLast ? nil : neighbourOffset,
                cutoutDiameter: size + ringWidth * 2
            )
            .fill(style: FillStyle(eoFill: true))
        }
    }

    /// Centre-to-centre distance to the next chip. Shapes aren't mirrored for
    /// right-to-left layouts the way the `HStack` is, so flip it by hand.
    private var neighbourOffset: CGFloat {
        let distance = size * (1 - overlap)
        return layoutDirection == .rightToLeft ? -distance : distance
    }
}

/// Stands in for the services the stack had no room for.
private struct OverflowAvatar: View {
    let count: Int
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color(red: 0.42, green: 0.45, blue: 0.50).gradient)
            .overlay {
                Text("+\(count)")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 1)
            }
            .overlay {
                Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .frame(width: size, height: size)
    }
}

/// A disc with a second, larger disc subtracted from it — filled even-odd, the
/// overlap drops out and leaves the neighbour's silhouette plus its gap.
private struct NeighbourCutout: Shape {
    /// Centre-to-centre distance to the neighbouring chip, or `nil` for the
    /// last chip, which nothing overlaps.
    var neighbourOffset: CGFloat?
    var cutoutDiameter: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(ellipseIn: rect)

        guard let neighbourOffset else { return path }

        path.addEllipse(in: CGRect(
            x: rect.midX + neighbourOffset - cutoutDiameter / 2,
            y: rect.midY - cutoutDiameter / 2,
            width: cutoutDiameter,
            height: cutoutDiameter
        ))

        return path
    }
}

// MARK: - Per-service chip styling

public enum ServiceAvatarStyle: Sendable {
    /// A tintable mark, drawn white on the brand-coloured disc.
    case glyph
    /// Artwork that carries its own colour and can't be flattened to a
    /// silhouette without turning into a blob.
    case artwork
}

extension MediaSearchService {
    public var avatarStyle: ServiceAvatarStyle {
        switch self {
        case .sonosRadio, .pandora:
            .artwork
        default:
            .glyph
        }
    }

    /// Colour of the disc behind the mark. Deliberately not `brandColor`: that
    /// resolves to `.primary` for the monochrome brands, which would leave a
    /// white glyph on a white disc, and some brand colours are too light to
    /// carry a white mark.
    public var avatarFill: Color {
        switch self {
        case .apple:
            Color(red: 250.0 / 255.0, green: 45.0 / 255.0, blue: 72.0 / 255.0)
        case .library:
            Color(red: 0.42, green: 0.45, blue: 0.50)
        case .plex:
            Color(red: 229.0 / 255.0, green: 160.0 / 255.0, blue: 13.0 / 255.0)
        case .spotify:
            Color(red: 30.0 / 255.0, green: 215.0 / 255.0, blue: 96.0 / 255.0)
        case .tidal:
            Color(red: 10.0 / 255.0, green: 11.0 / 255.0, blue: 9.0 / 255.0)
        case .tuneIn:
            Color(red: 28.0 / 255.0, green: 32.0 / 255.0, blue: 60.0 / 255.0)
        case .soundcloud:
            Color(red: 255.0 / 255.0, green: 85.0 / 255.0, blue: 0 / 255.0)
        case .deezer:
            Color(red: 161.0 / 255.0, green: 0 / 255.0, blue: 255.0 / 255.0)
        case .sonosRadio:
            .black
        case .pandora:
            .white
        case .subsonic:
            // Darker than `brandColor`'s amber, which leaves a white mark on
            // it at barely 2:1.
            Color(red: 214.0 / 255.0, green: 146.0 / 255.0, blue: 0 / 255.0)
        case .audiobookshelf:
            // Darker than `brandColor`'s tan, for the same reason.
            Color(red: 176.0 / 255.0, green: 112.0 / 255.0, blue: 56.0 / 255.0)
        case .files:
            // The system blue, a shade under `brandColor`'s folder blue.
            Color(red: 0 / 255.0, green: 122.0 / 255.0, blue: 255.0 / 255.0)
        }
    }

    /// The service mark as an untinted template, for the caller to colour.
    @ViewBuilder
    func avatarGlyph(size: CGFloat) -> some View {
        switch self {
        case .apple:
            SwiftUI.Image(systemName: "apple.logo")
                .resizable()
                .scaledToFit()
        case .library:
            SwiftUI.Image(systemName: avatarLibrarySymbolName)
                .resizable()
                .scaledToFit()
        case .subsonic:
            // A symbol rather than a bundle asset: Subsonic-compatible servers
            // don't share one brand mark.
            SwiftUI.Image(systemName: "externaldrive.fill.badge.icloud")
                .resizable()
                .scaledToFit()
        case .audiobookshelf:
            SwiftUI.Image(systemName: Self.audiobookshelfSymbolName)
                .resizable()
                .scaledToFit()
        case .files:
            SwiftUI.Image(systemName: "folder.fill")
                .resizable()
                .scaledToFit()
        default:
            #if targetEnvironment(macCatalyst)
            // Catalyst draws unrasterized asset images at their natural size,
            // so pre-rasterize to the chip's glyph size.
            if let base = UIImage(named: self.title, in: .module, with: nil) {
                let resized = base
                    .withRenderingMode(.alwaysTemplate)
                    .resized(to: CGSize(width: size, height: size))

                SwiftUI.Image(uiImage: resized)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            }
            #else
            SwiftUI.Image(self.title, bundle: .module)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
            #endif
        }
    }

    /// The service mark in its own colours, for badges that can't be templated.
    @ViewBuilder
    func avatarArtwork(size: CGFloat) -> some View {
        #if targetEnvironment(macCatalyst)
        if let base = UIImage(named: self.title, in: .module, with: nil) {
            SwiftUI.Image(uiImage: base.resized(to: CGSize(width: size, height: size)))
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
        }
        #else
        SwiftUI.Image(self.title, bundle: .module)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
        #endif
    }

    private var avatarLibrarySymbolName: String {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, watchOS 26.0, *) {
            "music.pages.fill"
        } else {
            "books.vertical.fill"
        }
    }
}

#Preview("Service avatars") {
    List {
        LabeledContent {
            ServiceAvatarStack(services: MediaSearchService.allCases)
        } label: {
            Text("Services")
        }

        LabeledContent {
            ServiceAvatarStack(services: MediaSearchService.allCases, maxVisible: 8)
        } label: {
            Text("Capped")
        }

        LabeledContent {
            ServiceAvatarStack(services: [.apple, .plex, .audiobookshelf, .files])
        } label: {
            Text("A few")
        }
    }
}
