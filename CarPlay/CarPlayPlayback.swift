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
    /// For the cards of an image row, and the details header's thumbnail.
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

    /// A system symbol in white on a dark screen and black on a light one.
    /// The car tints the tab bar's symbols but draws a row's or a button's
    /// as it gets them, and a plain symbol is black. Both looks go in the
    /// image's asset, for the car to switch as it goes from day to night;
    /// the one handed over is the screen's look now.
    static func symbol(_ name: String) -> UIImage? {
        guard let symbol = UIImage(systemName: name) else { return nil }
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let asset = UIImageAsset()
        asset.register(symbol.withTintColor(.black, renderingMode: .alwaysOriginal), with: UITraitCollection(userInterfaceStyle: .light))
        asset.register(symbol.withTintColor(.white, renderingMode: .alwaysOriginal), with: dark)
        return asset.image(with: screen?.carTraitCollection ?? dark)
    }
}
#endif
