#if os(iOS) && !targetEnvironment(macCatalyst)
import CarPlay
import Defaults
import Foundation
import Nuke
import OSLog
import SonosKit
import UIKit

/// Plays what's picked on the car's screen.
///
/// Always on this device, whatever the phone was last pointed at: something
/// picked in the car is meant to be heard in the car. The route is moved to
/// this device without carrying anything, so whatever was playing elsewhere
/// is left as it was — someone may still be listening there.
@MainActor
enum CarPlayPlayback {
    /// `log stream --predicate 'subsystem == "dance.cue" AND category == "carplay"' --level debug`
    private static let log = Logger(subsystem: "dance.cue", category: "carplay")

    /// Plays `contents` from the top, containers expanded in place.
    static func play(_ contents: [PlayableContent], shuffle: Bool = false) async throws {
        guard let first = contents.first else { return }
        takeRoute()
        log.notice("play \(first.content.id, privacy: .public) count=\(contents.count) shuffle=\(shuffle)")
        try await LocalPlaybackService.shared.enqueue(contents, at: .now, shuffle: shuffle)
        record(first)
    }

    /// Plays `items` from `index` on, as a list of songs: a song picked in
    /// the downloads' Songs list plays the list from there.
    static func play(_ items: [PlayableContent], startingAt index: Int) async throws {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        takeRoute()
        log.notice("play \(item.content.id, privacy: .public) at \(index) of \(items.count)")
        try await LocalPlaybackService.shared.play(items, startingAt: index)
        record(item)
    }

    /// Plays `container` from `track` on, the way a tap on a song in an
    /// album or playlist does on the phone. Falls back to the song alone
    /// when the container no longer holds it.
    static func play(_ track: PlayableContent, in container: PlayableContent) async throws {
        takeRoute()
        log.notice("play \(track.content.id, privacy: .public) in \(container.content.id, privacy: .public)")
        let player = LocalPlaybackService.shared
        let played = try await player.play(track, in: container)
        if !played {
            try await player.enqueue([track], at: .now, from: container)
        }
        record(track)
    }

    /// Plays the device's queue from where it stopped: just paused, or
    /// restored from the last launch or parked by a hand-off with nothing
    /// armed yet, which Play arms at the saved spot.
    static func resume() {
        let player = LocalPlaybackService.shared
        guard player.isActive else { return }
        takeRoute()
        guard !player.isPlaying else { return }
        log.notice("resume \(player.nowPlaying?.content.id ?? "-", privacy: .public)")
        player.togglePlayback()
    }

    /// Points the route at this device if it's elsewhere. See the type's
    /// comment for why nothing is carried.
    private static func takeRoute() {
        let route = PlaybackRoute.shared
        guard route.destination != .device else { return }
        log.notice("route → device for a play from CarPlay")
        route.switchTo(.device, carrying: false)
    }

    /// Into Recently Played, the same as a play from the phone — see
    /// `PlayDestinationRouter.record`. Not Shuffle All over the downloads:
    /// On This Device is a way to play, not something to go back to.
    private static func record(_ item: PlayableContent) {
        guard !OnDeviceLibrary.isAllSongs(item) else { return }
        let history = PlayHistoryService.shared
        history.history.remove(item)
        history.history.insert(item, at: 0)
    }
}

/// Artwork for the car's lists, through the shared Nuke pipeline under the
/// key the phone's artwork views use, so a cover already seen there usually
/// comes straight from the cache.
@MainActor
enum CarPlayArtwork {
    /// Comfortably over `CPListItem.maximumImageSize` on any car's screen;
    /// the system scales it down.
    static let rowWidth: CGFloat = 120
    /// For the cards and squares of an image row, and the details header's
    /// thumbnail.
    static let cardWidth: CGFloat = 400

    /// The car's screen, for its light or dark look (see `symbol(_:)`).
    static weak var screen: CPInterfaceController?

    /// Sets `content`'s cover on `item` once it's loaded. The row keeps its
    /// placeholder symbol until then, and for good when there's no cover.
    static func load(_ content: PlayableContent, into item: CPListItem) {
        load(content, width: rowWidth) { [weak item] image in
            item?.setImage(image)
        }
    }

    /// Hands `content`'s cover to `apply` once it's loaded — at once when
    /// it's cached. Never called when there's no cover or it won't load.
    static func load(_ content: PlayableContent, width: CGFloat, _ apply: @escaping @MainActor (UIImage) -> Void) {
        guard let url = content.thumbnail ?? content.artwork else { return }
        var request = ImageRequest(url: url, processors: [.resize(width: width)])
        request.imageID = content.imageKey
        if let cached = ImagePipeline.shared.cache.cachedImage(for: request)?.image {
            apply(cached)
            return
        }
        Task {
            guard let image = try? await ImagePipeline.shared.image(for: request) else { return }
            apply(image)
        }
    }

    /// What a row shows before its cover arrives: the content type's symbol.
    static func placeholder(for content: PlayableContent) -> UIImage? {
        symbol(content.content.type.symbol)
    }

    /// The same, never nil, for the APIs that won't take a missing image.
    static func requiredPlaceholder(for content: PlayableContent) -> UIImage {
        placeholder(for: content) ?? symbol("music.note") ?? UIImage()
    }

    /// A system symbol in white on a dark screen and black on a light one
    /// (`looks`). The car tints the tab bar's symbols but draws a row's as
    /// it gets them, and a plain symbol is black.
    static func symbol(_ name: String) -> UIImage? {
        guard let symbol = UIImage(systemName: name) else { return nil }
        return looks { color in symbol.withTintColor(color, renderingMode: .alwaysOriginal) }
    }

    /// A tile's symbol (`CarPlayInterface.tileRow`), drawn whole in the
    /// middle of a square the size the car draws a tile's image at. The car
    /// resizes what it's given to that square, which would stretch a symbol
    /// that isn't square (most aren't), and a bare symbol fills it edge to
    /// edge. White and black, as `symbol(_:)`.
    static func tile(_ name: String) -> UIImage {
        let maximum = CPListImageRowItemCondensedElement.maximumImageSize
        let side = min(maximum.width, maximum.height) > 0 ? min(maximum.width, maximum.height) : 44
        let configuration = UIImage.SymbolConfiguration(pointSize: side / 2, weight: .medium)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else { return UIImage() }
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(screen?.carTraitCollection.displayScale ?? 2, 1)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        // A little over half the square, whichever way the symbol is longer.
        let fit = min(1, side * 0.6 / max(symbol.size.width, symbol.size.height, 1))
        let size = CGSize(width: symbol.size.width * fit, height: symbol.size.height * fit)
        let frame = CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height)
        return looks { color in
            renderer.image { _ in
                symbol.withTintColor(color, renderingMode: .alwaysOriginal).draw(in: frame)
            }
        }
    }

    /// The phone's queue button (`QueueIconView`) for the car's Now Playing:
    /// a ring filled as far through the queue as the song playing, with its
    /// place in the middle. Zero under a station, which leaves the queue
    /// waiting, as a speaker's reads on radio: the ring stays, its place
    /// doesn't. Past 999 the ring is shown alone, as on the phone. Drawn
    /// whole at the size the car draws a Now Playing button's image at.
    static func queueGauge(position: Int, total: Int) -> UIImage {
        let maximum = CPNowPlayingButtonMaximumImageSize
        let side = min(maximum.width, maximum.height) > 0 ? min(maximum.width, maximum.height) : 40
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(screen?.carTraitCollection.displayScale ?? 2, 1)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        // The phone's proportions: a 2 pt line on a 24 pt ring.
        let lineWidth = max(2, side / 12)
        let inset = side * 0.08 + lineWidth / 2
        let ring = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
        let fraction = total > 0 ? min(1, CGFloat(position) / CGFloat(total)) : 0
        let text = position < 1000 ? "\(position)" : nil
        return looks { color in
            renderer.image { _ in
                let track = UIBezierPath(ovalIn: ring)
                track.lineWidth = lineWidth
                color.withAlphaComponent(0.25).setStroke()
                track.stroke()
                if fraction > 0 {
                    let start = -CGFloat.pi / 2
                    let arc = UIBezierPath(
                        arcCenter: CGPoint(x: ring.midX, y: ring.midY),
                        radius: ring.width / 2,
                        startAngle: start,
                        endAngle: start + 2 * .pi * fraction,
                        clockwise: true
                    )
                    arc.lineWidth = lineWidth
                    arc.lineCapStyle = .round
                    color.setStroke()
                    arc.stroke()
                }
                guard let text else { return }
                // As large as fits inside the ring: three digits shrink.
                let room = ring.width - lineWidth * 2 - side * 0.1
                var font = roundedDigits(size: side * 0.36)
                while (text as NSString).size(withAttributes: [.font: font]).width > room, font.pointSize > side * 0.18 {
                    font = roundedDigits(size: font.pointSize - 0.5)
                }
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let width = (text as NSString).size(withAttributes: attributes).width
                // Centred on the digits' height rather than the line's.
                let origin = CGPoint(x: ring.midX - width / 2, y: ring.midY + font.capHeight / 2 - font.ascender)
                (text as NSString).draw(at: origin, withAttributes: attributes)
            }
        }
    }

    /// The phone's queue count: rounded, with digits of one width.
    private static func roundedDigits(size: CGFloat) -> UIFont {
        let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        guard let rounded = font.fontDescriptor.withDesign(.rounded) else { return font }
        return UIFont(descriptor: rounded, size: size)
    }

    /// An image in black for a light screen and white for a dark one, both
    /// in its asset, for the car to switch as it goes from day to night; the
    /// one handed over is the screen's look now.
    private static func looks(_ draw: (UIColor) -> UIImage) -> UIImage {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let asset = UIImageAsset()
        asset.register(draw(.black), with: UITraitCollection(userInterfaceStyle: .light))
        asset.register(draw(.white), with: dark)
        return asset.image(with: screen?.carTraitCollection ?? dark)
    }
}
#endif
