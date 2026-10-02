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
/// Always on this device, whatever the route says: something picked in the
/// car is meant to be heard in the car, and with the route on a speaker it
/// would start at home instead. The route is moved to this device without
/// carrying, so a speaker that was playing goes on playing its own queue —
/// someone may still be listening there. Getting the music back onto a
/// speaker is the Play On list's job.
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
    /// restored from the last launch with nothing armed yet, which Play arms
    /// at the saved spot.
    static func resume() {
        let player = LocalPlaybackService.shared
        guard player.isActive, !player.isPlaying else { return }
        log.notice("resume \(player.nowPlaying?.content.id ?? "-", privacy: .public)")
        player.togglePlayback()
    }

    /// Moves the route to this device if it's on a speaker. See the type's
    /// comment for why nothing is carried.
    private static func takeRoute() {
        let route = PlaybackRoute.shared
        guard route.destination != .device else { return }
        log.notice("route → device for a play from CarPlay")
        route.switchTo(.device, carrying: false)
    }

    /// Into Recently Played, the same as a play from the phone — see
    /// `PlayDestinationRouter.record`.
    private static func record(_ item: PlayableContent) {
        let history = PlayHistoryService.shared
        history.history.remove(item)
        history.history.insert(item, at: 0)
    }
}

/// Artwork for the car's list rows, through the shared Nuke pipeline under
/// the key the phone's artwork views use, so a cover already seen there
/// usually comes straight from the cache.
@MainActor
enum CarPlayArtwork {
    /// Comfortably over `CPListItem.maximumImageSize` on any car's screen;
    /// the system scales it down.
    private static let width: CGFloat = 120

    /// Sets `content`'s cover on `item` once it's loaded. The row keeps its
    /// placeholder symbol until then, and for good when there's no cover.
    static func load(_ content: PlayableContent, into item: CPListItem) {
        guard let url = content.thumbnail ?? content.artwork else { return }
        var request = ImageRequest(url: url, processors: [.resize(width: width)])
        request.imageID = content.imageKey
        if let cached = ImagePipeline.shared.cache.cachedImage(for: request)?.image {
            item.setImage(cached)
            return
        }
        Task { [weak item] in
            guard let image = try? await ImagePipeline.shared.image(for: request) else { return }
            item?.setImage(image)
        }
    }

    /// What a row shows before its cover arrives: the content type's symbol.
    static func placeholder(for content: PlayableContent) -> UIImage? {
        UIImage(systemName: content.content.type.symbol)
    }
}
#endif
