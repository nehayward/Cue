import Foundation
import MediaPlayer
import Nuke
import OSLog
import SonosKit
import UIKit

/// The Lock Screen and Control Center card for on-device stream playback —
/// Plex, Subsonic and Files through `AVQueuePlayer`. Apple Music plays in
/// MusicKit's own player, which publishes for itself; the stream player
/// publishes nothing unless told, which is what this does: the song, its
/// artwork and timeline, and the transport commands, for as long as a run
/// is armed.
///
/// While CarPlay is connected it publishes Apple Music runs as well. On
/// iOS 27 the car's Now Playing screen reads this app's own client rather
/// than MusicKit's, so Apple Music needs a card here to show up there at
/// all (`LocalPlaybackService.publishesAppleMusicCard`).
///
/// A station's card is live (`MPNowPlayingInfoPropertyIsLiveStream`): the
/// LIVE bar in place of a timeline, and play and pause alone. iOS draws a
/// live card's pause as a stop button (the Music app's radio is the same),
/// so the stop command pauses; skipping, scrubbing, shuffle and repeat are
/// switched off, which greys out what the system won't hide. An Apple Music
/// station that skips its own songs keeps Next.
///
/// The Sonos mirror (`NowPlayingSessionService`) stands down while local
/// audio plays, and on its way out it clears the card. The presenter notices
/// its card is gone on the next poll and puts it back, so the two hand off
/// whichever order the system runs them in.
@MainActor
final class LocalNowPlayingPresenter {
    private weak var player: LocalPlaybackService?

    private struct Snapshot: Equatable {
        var identity: String
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval
        var isPlaying: Bool
        var artworkURL: URL?
        var canSkip: Bool
        var isLive: Bool
    }

    private var published: Snapshot?
    private var publishedElapsed: TimeInterval = 0
    /// When `publishedElapsed` was stated, for where the system's clock
    /// should be now.
    private var publishedAt = Date.distantPast
    private var commandTokens: [(MPRemoteCommand, Any)] = []
    private var artworkTask: Task<Void, Never>?
    private var publishedArtworkURL: URL?
    private var publishedArtwork: MPMediaItemArtwork?
    /// Whether the last update asked for the clock to be restated (see
    /// `update`), so a seek's publish states the card the same way.
    private var restatesClock = false

    /// Marks the card as this presenter's, so it can tell when something
    /// else has replaced or cleared it. In the collection identifier, not
    /// `MPNowPlayingInfoPropertyExternalContentIdentifier`: a card carrying
    /// that one runs into CarPlay's metadata throttle ("Application exceeded
    /// audio metadata throttle limit"), after which the car's Now Playing
    /// screen stops taking the card's updates.
    private static let marker = "cue.local"

    /// How often a card that restates its clock is published again (see
    /// `update`). Once a second ran the car's clock smoothly, but at rate 0
    /// every restate is a real change, a write a second, and CarPlay's
    /// metadata throttle ("Application exceeded audio metadata throttle
    /// limit") is there to stop that: past it the car's Now Playing takes no
    /// more updates. With restates every second, a new song or a new queue
    /// played on with the old one still showing in the car. A song change
    /// still publishes at once; this only spaces the restates in between, so
    /// the clock steps every few seconds.
    private static let restateInterval: TimeInterval = 5

    private static let log = Logger(subsystem: "dance.cue", category: "nowplaying")

    init(player: LocalPlaybackService) {
        self.player = player
    }

    // MARK: - Lifecycle

    /// A stream run is armed: take the commands.
    func begin() {
        guard commandTokens.isEmpty else { return }
        registerCommands()
    }

    /// The run is torn down: clear the card if it's ours, give the commands
    /// back.
    func end() {
        artworkTask?.cancel()
        artworkTask = nil
        unregisterCommands()
        if isOurs(MPNowPlayingInfoCenter.default().nowPlayingInfo) {
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        published = nil
        publishedArtworkURL = nil
        publishedArtwork = nil
        restatesClock = false
    }

    /// Called from the player's poll. Publishes when the song, its state or
    /// its length changed, or when the card isn't ours any more; the
    /// elapsed time is left to the system's own clock between publishes,
    /// which is smoother than pushing a number twice a second.
    ///
    /// `restatesClock` publishes every `restateInterval` while playing, for
    /// a card the system won't run the clock on. That's Apple Music's in a
    /// car: iOS reads a card as playing only while this process makes the
    /// sound (`playbackState` is macOS-only), MusicKit's player makes it
    /// out of process, and on iOS 27 the car reads this card all the same
    /// (FB24840951) — so it froze at the last publish. Stepping beats
    /// standing still; the car's play/pause glyph stays wrong regardless.
    /// Such a card is stated at rate 0, as the car reads it anyway: at rate
    /// 1 each restate says only what the system's own clock already
    /// predicts, which it can take as no change at all.
    ///
    /// `isLive` is a station's card: no timeline, so no restates and no
    /// drift to correct, only a write when what's on air or the play state
    /// changes. The station's name goes where an album's would.
    func update(
        item: PlayableContent?,
        isPlaying: Bool,
        duration: TimeInterval,
        elapsed: TimeInterval,
        canSkip: Bool,
        isLive: Bool = false,
        restatesClock: Bool = false
    ) {
        guard let item else { return }
        self.restatesClock = restatesClock && !isLive
        // The station's name where an album's would go, unless it's the
        // title already (nothing said to be on air yet).
        var album = item.metadata?.album ?? ""
        if isLive, let station = player?.nowPlaying?.title, station != item.title {
            album = station
        }
        let snapshot = Snapshot(
            identity: item.content.id,
            title: item.title,
            artist: item.metadata?.artist ?? item.subtitle,
            album: album,
            duration: isLive || !duration.isFinite ? 0 : duration,
            isPlaying: isPlaying,
            artworkURL: item.artwork ?? item.thumbnail,
            canSkip: canSkip,
            isLive: isLive
        )
        let cardIsOurs = isOurs(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        // A stall or a hiccup can leave the system's clock well off, and so
        // can a seek this player never saw (MusicKit's own card takes
        // those for Apple Music); a drift past a couple of seconds is worth
        // a republish. The clock runs on from the last publish while
        // playing and stands still while paused.
        let expected = published?.isPlaying == true
            ? publishedElapsed + Date.now.timeIntervalSince(publishedAt)
            : publishedElapsed
        let drifted = !isLive && abs(elapsed - expected) > 2
        let restate = self.restatesClock && isPlaying && Date.now.timeIntervalSince(publishedAt) >= Self.restateInterval
        guard snapshot != published || !cardIsOurs || drifted || restate else { return }
        publish(snapshot, elapsed: elapsed, item: item)
    }

    /// A seek moves the timeline; the card has to know now.
    func noteSeek(elapsed: TimeInterval) {
        guard let published, !published.isLive, let player else { return }
        publish(published, elapsed: elapsed, item: player.nowPlayingDisplay)
    }

    // MARK: - Publishing

    private func publish(_ snapshot: Snapshot, elapsed: TimeInterval, item: PlayableContent?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPMediaItemPropertyArtist: snapshot.artist,
            MPMediaItemPropertyAlbumTitle: snapshot.album,
            MPNowPlayingInfoCollectionIdentifier: Self.marker,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.isPlaying && !restatesClock ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyIsLiveStream: snapshot.isLive,
        ]
        // A live card has no timeline: LIVE stands where the time would.
        if !snapshot.isLive {
            if snapshot.duration > 0 {
                info[MPMediaItemPropertyPlaybackDuration] = snapshot.duration
            }
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, elapsed)
        }

        if let publishedArtwork, publishedArtworkURL == snapshot.artworkURL {
            info[MPMediaItemPropertyArtwork] = publishedArtwork
        }

        // Ahead of the card, so the card is drawn with the buttons that go
        // with it: a station's comes up with no skips to take away after.
        let center = MPRemoteCommandCenter.shared()
        Self.set(center.nextTrackCommand, enabled: snapshot.canSkip)
        Self.set(center.previousTrackCommand, enabled: !snapshot.isLive)
        Self.set(center.changePlaybackPositionCommand, enabled: !snapshot.isLive && snapshot.duration > 0)
        Self.set(center.stopCommand, enabled: snapshot.isLive)
        // The Sonos mirror switches these off for its card; this card is
        // back, and so are they — bar a station's, which has neither.
        Self.set(center.changeShuffleModeCommand, enabled: !snapshot.isLive)
        Self.set(center.changeRepeatModeCommand, enabled: !snapshot.isLive)

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = snapshot.isPlaying ? .playing : .paused

        published = snapshot
        publishedElapsed = max(0, elapsed)
        publishedAt = .now
        if restatesClock {
            Self.log.debug("car card: \(snapshot.title, privacy: .public) at \(elapsed, format: .fixed(precision: 0))s, \(snapshot.isPlaying ? "playing" : "paused", privacy: .public)")
        } else if snapshot.isLive {
            Self.log.debug("live card: \(snapshot.title, privacy: .public) on \(snapshot.album, privacy: .public), \(snapshot.isPlaying ? "playing" : "paused", privacy: .public)")
        }

        if publishedArtworkURL != snapshot.artworkURL {
            loadArtwork(from: snapshot.artworkURL, item: item)
        }
    }

    private func isOurs(_ info: [String: Any]?) -> Bool {
        (info?[MPNowPlayingInfoCollectionIdentifier] as? String) == Self.marker
    }

    /// Sets a command's state only when it changes, so a republish (a
    /// restate, a new song) isn't also a round of command updates for the
    /// system to pass on to a car.
    private static func set(_ command: MPRemoteCommand, enabled: Bool) {
        if command.isEnabled != enabled {
            command.isEnabled = enabled
        }
    }

    /// Through the shared Nuke pipeline with the player cover's own request,
    /// so the image is usually already decoded; file URLs from the Files
    /// folder and the download cache load the same way. Its own request (a
    /// resize to 500 px) had a key of its own: every song was decoded again
    /// at full size, then scaled.
    private func loadArtwork(from url: URL?, item: PlayableContent?) {
        artworkTask?.cancel()
        publishedArtworkURL = url
        guard let url else {
            publishedArtwork = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = nil
            return
        }
        var request = item.map {
            ContentArtworkView.artworkRequest(for: $0, url: url, preferredSize: ContentArtworkView.playerPreferredSize)
        } ?? ImageRequest(url: url, processors: [.resize(width: 500)])
        request.priority = .high
        if let cached = ImagePipeline.shared.cache.cachedImage(for: request)?.image {
            attach(artwork: cached, for: url)
            return
        }
        artworkTask = Task { [weak self] in
            guard let image = try? await ImagePipeline.shared.image(for: request) else { return }
            guard !Task.isCancelled else { return }
            self?.attach(artwork: image, for: url)
        }
    }

    private func attach(artwork image: UIImage, for url: URL) {
        guard publishedArtworkURL == url else { return }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        publishedArtwork = artwork
        if isOurs(MPNowPlayingInfoCenter.default().nowPlayingInfo) {
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
        }
    }

    // MARK: - Remote commands

    /// Handlers arrive on the main thread, hence `assumeIsolated`. Only this
    /// presenter's targets are removed on the way out, so the Sonos mirror's
    /// handlers, if any are registered, are left alone.
    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.changeShuffleModeCommand.isEnabled = true
        center.changeRepeatModeCommand.isEnabled = true
        // Only a live card's (see `publish`).
        center.stopCommand.isEnabled = false

        func add(_ command: MPRemoteCommand, _ action: @escaping @MainActor (LocalPlaybackService, MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
            let token = command.addTarget { [weak self] event in
                MainActor.assumeIsolated {
                    guard let player = self?.player else { return .noSuchContent }
                    return action(player, event)
                }
            }
            commandTokens.append((command, token))
        }

        add(center.playCommand) { player, _ in
            if !player.isPlaying { player.togglePlayback() }
            return .success
        }
        add(center.pauseCommand) { player, _ in
            if player.isPlaying { player.togglePlayback() }
            return .success
        }
        add(center.togglePlayPauseCommand) { player, _ in
            player.togglePlayback()
            return .success
        }
        // A live card's pause button, as iOS draws it.
        add(center.stopCommand) { player, _ in
            if player.isPlaying { player.pause() }
            return .success
        }
        add(center.nextTrackCommand) { player, _ in
            player.next()
            return .success
        }
        add(center.previousTrackCommand) { player, _ in
            player.previous()
            return .success
        }
        add(center.changePlaybackPositionCommand) { player, event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            player.seek(to: event.positionTime)
            return .success
        }
        // A car's shuffle and repeat buttons (`CarPlayInterface`) take a tap
        // only while these commands are there to take one: without them the
        // buttons drew but did nothing. Siri and accessories send them as
        // they are. A station has neither.
        add(center.changeShuffleModeCommand) { player, event in
            guard let event = event as? MPChangeShuffleModeCommandEvent, !player.isPlayingStation else { return .commandFailed }
            player.setShuffle(event.shuffleType != .off)
            return .success
        }
        add(center.changeRepeatModeCommand) { player, event in
            guard let event = event as? MPChangeRepeatModeCommandEvent, !player.isPlayingStation else { return .commandFailed }
            player.setRepeatMode(LocalPlaybackService.RepeatMode(event.repeatType))
            return .success
        }
    }

    private func unregisterCommands() {
        for (command, token) in commandTokens {
            command.removeTarget(token)
        }
        commandTokens = []
        // Nothing else takes it; left on, it would outlive the card.
        MPRemoteCommandCenter.shared().stopCommand.isEnabled = false
    }
}

extension LocalPlaybackService.RepeatMode {
    /// From the system's repeat type, as a remote command or a car states it.
    init(_ type: MPRepeatType) {
        switch type {
        case .one: self = .one
        case .all: self = .all
        default: self = .off
        }
    }

    /// As the system's remote commands state it.
    var repeatType: MPRepeatType {
        switch self {
        case .off: .off
        case .all: .all
        case .one: .one
        }
    }
}
