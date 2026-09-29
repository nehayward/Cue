import Foundation
import MediaPlayer
import Nuke
import SonosKit
import UIKit

/// The Lock Screen and Control Center card for on-device stream playback —
/// Plex, Subsonic and Files through `AVQueuePlayer`. Apple Music plays in
/// MusicKit's own player, which publishes for itself; the stream player
/// publishes nothing unless told, which is what this does: the song, its
/// artwork and timeline, and the transport commands, for as long as a run
/// is armed.
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
        /// A station that can be taken back: skip-interval buttons in place
        /// of previous.
        var canTimeShift: Bool
    }

    /// The Lock Screen's skip interval for a station, both ways.
    private static let timeShiftInterval: TimeInterval = 60

    private var published: Snapshot?
    private var publishedElapsed: TimeInterval = 0
    private var commandTokens: [(MPRemoteCommand, Any)] = []
    private var artworkTask: Task<Void, Never>?
    private var publishedArtworkURL: URL?
    private var publishedArtwork: MPMediaItemArtwork?

    /// Marks the card as this presenter's, so it can tell when something
    /// else has replaced or cleared it.
    private static let identifierPrefix = "cue.local."

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
    }

    /// Called from the player's poll. Publishes when the song, its state or
    /// its length changed, or when the card isn't ours any more; the
    /// elapsed time is left to the system's own clock between publishes,
    /// which is smoother than pushing a number twice a second.
    func update(item: PlayableContent?, isPlaying: Bool, duration: TimeInterval, elapsed: TimeInterval, canSkip: Bool) {
        guard let item else { return }
        let snapshot = Snapshot(
            identity: item.content.id,
            title: item.title,
            artist: item.metadata?.artist ?? item.subtitle,
            album: item.metadata?.album ?? "",
            duration: duration.isFinite ? duration : 0,
            isPlaying: isPlaying,
            artworkURL: item.artwork ?? item.thumbnail,
            canSkip: canSkip,
            canTimeShift: player?.timeShift != nil
        )
        let cardIsOurs = isOurs(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        // A stall or a hiccup can leave the system's clock well off; a
        // drift past a couple of seconds is worth a republish.
        let drifted = abs(elapsed - publishedElapsed) > 2 && !isPlaying
        guard snapshot != published || !cardIsOurs || drifted else { return }
        publish(snapshot, elapsed: elapsed, item: item)
    }

    /// A seek moves the timeline; the card has to know now.
    func noteSeek(elapsed: TimeInterval) {
        guard let published, let player else { return }
        publish(published, elapsed: elapsed, item: player.nowPlaying)
        publishedElapsed = elapsed
    }

    // MARK: - Publishing

    private func publish(_ snapshot: Snapshot, elapsed: TimeInterval, item: PlayableContent?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPMediaItemPropertyArtist: snapshot.artist,
            MPMediaItemPropertyAlbumTitle: snapshot.album,
            MPNowPlayingInfoPropertyExternalContentIdentifier: Self.identifierPrefix + snapshot.identity,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]
        if snapshot.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = snapshot.duration
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, elapsed)

        if let publishedArtwork, publishedArtworkURL == snapshot.artworkURL {
            info[MPMediaItemPropertyArtwork] = publishedArtwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = snapshot.isPlaying ? .playing : .paused

        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = snapshot.canSkip && !snapshot.canTimeShift
        center.previousTrackCommand.isEnabled = !snapshot.canTimeShift
        center.skipBackwardCommand.isEnabled = snapshot.canTimeShift
        center.skipForwardCommand.isEnabled = snapshot.canTimeShift
        center.changePlaybackPositionCommand.isEnabled = snapshot.duration > 0

        published = snapshot
        publishedElapsed = elapsed

        if publishedArtworkURL != snapshot.artworkURL {
            loadArtwork(from: snapshot.artworkURL, item: item)
        }
    }

    private func isOurs(_ info: [String: Any]?) -> Bool {
        (info?[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String)?.hasPrefix(Self.identifierPrefix) ?? false
    }

    /// Through the shared Nuke pipeline under the same key the artwork views
    /// use, so the image is usually already decoded; file URLs from the
    /// Files folder and the download cache load the same way.
    private func loadArtwork(from url: URL?, item: PlayableContent?) {
        artworkTask?.cancel()
        publishedArtworkURL = url
        guard let url else {
            publishedArtwork = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = nil
            return
        }
        var request = ImageRequest(url: url, processors: [.resize(width: 500)], priority: .high)
        if let item {
            request.imageID = item.imageKey
        }
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
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.timeShiftInterval)]
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.timeShiftInterval)]

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
        add(center.nextTrackCommand) { player, _ in
            player.next()
            return .success
        }
        add(center.previousTrackCommand) { player, _ in
            player.previous()
            return .success
        }
        add(center.skipBackwardCommand) { player, event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? Self.timeShiftInterval
            player.skipLive(by: -interval)
            return .success
        }
        add(center.skipForwardCommand) { player, event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? Self.timeShiftInterval
            player.skipLive(by: interval)
            return .success
        }
        add(center.changePlaybackPositionCommand) { player, event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            player.seek(to: event.positionTime)
            return .success
        }
    }

    private func unregisterCommands() {
        for (command, token) in commandTokens {
            command.removeTarget(token)
        }
        commandTokens = []
        let center = MPRemoteCommandCenter.shared()
        center.skipBackwardCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
    }
}
