import AVFoundation
import Defaults
import Foundation
import MediaPlayer
import Nuke
import OSLog
import SonosKit
import UIKit

/// The Lock Screen and Control Center card for on-device stream playback —
/// Plex, Subsonic, Files and TuneIn through `AVQueuePlayer`. Apple Music plays in
/// MusicKit's own player, which publishes for itself; the stream player
/// publishes nothing unless told, which is what this does: the song, its
/// artwork and timeline, and the transport commands, for as long as a run
/// is armed. From one stream run to the next the card stays up, and the new
/// run puts its song on it (`noteHandOff`).
///
/// A TuneIn station's card is live (`MPNowPlayingInfoPropertyIsLiveStream`):
/// the LIVE bar in place of a timeline, and play and pause alone. iOS draws
/// a live card's pause as a stop button (the Music app's radio is the same),
/// so the stop command pauses; skipping, scrubbing, shuffle and repeat are
/// switched off, which greys out what the system won't hide.
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
        /// A book's file: skips by interval instead of by track, at the
        /// book's speed.
        var isBook = false
        var rate: Double = 1
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

    /// Marks the card as this presenter's, so it can tell when something
    /// else has replaced or cleared it.
    private static let identifierPrefix = "cue.local."

    private static let log = Logger(subsystem: "dance.cue", category: "nowplaying")

    init(player: LocalPlaybackService) {
        self.player = player
    }

    // MARK: - Now Playing session

    /// With Settings ▸ Debug ▸ Now Playing Session on: the card and its
    /// commands belong to an `MPNowPlayingSession` of the stream player, so
    /// the system knows which player they speak for (the car's Now Playing
    /// sticking on MusicKit's card, FB24840951, is the hope). Off, they go
    /// to the app's shared center as before. Taken at the first stream
    /// player after the card was down, given each player that follows, and
    /// dropped with the card (`end()`).
    private var session: MPNowPlayingSession?

    private var infoCenter: MPNowPlayingInfoCenter {
        session?.nowPlayingInfoCenter ?? .default()
    }

    private var commandCenter: MPRemoteCommandCenter {
        session?.remoteCommandCenter ?? .shared()
    }

    /// A stream player was made for a run: the card moves to a session of
    /// it. Ahead of `begin()`, so the commands go to the session's center.
    ///
    /// A session a player, never a player swapped inside one: with
    /// automatic publishing off, `removePlayer(_:)` takes away KVO it never
    /// added, and the exception took the app down (Back to Book, a new
    /// stream run). So a new player gets a new session, the commands and
    /// the song move over to it, and the old session goes.
    func attach(_ player: AVPlayer) {
        guard UserDefaults.standard.bool(forKey: AppStorageKeys.nowPlayingSession) else { return }
        if let session, session.players.contains(where: { $0 === player }) { return }
        let hadCommands = !commandTokens.isEmpty
        // Commands already up on the shared center (the switch turned on
        // mid-run) stay there until the card comes down.
        if session == nil, hadCommands { return }
        if hadCommands {
            unregisterCommands()
        }
        let session = MPNowPlayingSession(players: [player])
        session.automaticallyPublishesNowPlayingInfo = false
        self.session = session
        if hadCommands {
            registerCommands()
        }
        // The next update puts the song on the new session's card.
        published = nil
        session.becomeActiveIfPossible { active in
            Self.log.notice("now playing session \(active ? "active" : "not active", privacy: .public)")
        }
    }

    // MARK: - Lifecycle

    /// Whether a card of this presenter's is up.
    var isUp: Bool { published != nil }

    /// A stream run is armed: take the commands.
    func begin() {
        guard commandTokens.isEmpty else { return }
        registerCommands()
    }

    /// The run is torn down for another stream run, which puts its own song
    /// on this card: it stays up meanwhile, commands and all, rather than
    /// going to nothing for a moment. A car's Now Playing that saw this
    /// player stop with no song and no commands let go of it, and didn't
    /// come back to it for the next song.
    func noteHandOff() {
        guard let title = published?.title else { return }
        Self.log.notice("card kept for the next stream run, from \(title, privacy: .public)")
    }

    /// The run is torn down: clear the card if it's ours, give the commands
    /// back. Nothing to do when neither is up.
    func end() {
        guard published != nil || !commandTokens.isEmpty else { return }
        let from = published.map { ", from \($0.title)" } ?? ""
        Self.log.notice("card down\(from, privacy: .public)")
        artworkTask?.cancel()
        artworkTask = nil
        unregisterCommands()
        if isOurs(infoCenter.nowPlayingInfo) {
            infoCenter.playbackState = .stopped
            infoCenter.nowPlayingInfo = nil
        }
        published = nil
        publishedArtworkURL = nil
        publishedArtwork = nil
        // The app's own card is the shared center's again, for the Sonos
        // mirror and whatever plays next.
        session = nil
    }

    /// Called from the player's poll. Publishes when the song, its state or
    /// its length changed, or when the card isn't ours any more; the
    /// elapsed time is left to the system's own clock between publishes,
    /// which is smoother than pushing a number twice a second.
    ///
    /// `isLive` is a station's card: no timeline, so no drift to correct,
    /// only a write when what's on air or the play state changes. The
    /// station's name goes where an album's would.
    func update(
        item: PlayableContent?,
        isPlaying: Bool,
        duration: TimeInterval,
        elapsed: TimeInterval,
        canSkip: Bool,
        isLive: Bool = false
    ) {
        guard let item else { return }
        // The station's name where an album's would go, unless it's the
        // title already (nothing said to be on air yet).
        var album = item.metadata?.album ?? ""
        if isLive, let station = player?.nowPlaying?.title, station != item.title {
            album = station
        }
        var snapshot = Snapshot(
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
        // A book reads as its chapter, by its author, in the book.
        let books = AudiobookPlayer.shared
        if let book = books.current, books.contains(item) {
            snapshot.isBook = true
            snapshot.rate = books.rate
            snapshot.title = books.currentChapter?.title ?? item.title
            snapshot.album = book.book.title
            snapshot.artist = book.book.subtitle
            snapshot.artworkURL = book.book.artwork ?? snapshot.artworkURL
        }
        let cardIsOurs = isOurs(infoCenter.nowPlayingInfo)
        // A stall or a hiccup can leave the system's clock well off; a
        // drift past a couple of seconds is worth a republish. The clock
        // runs on from the last publish while playing and stands still
        // while paused.
        let expected = published?.isPlaying == true
            ? publishedElapsed + Date.now.timeIntervalSince(publishedAt) * (published?.rate ?? 1)
            : publishedElapsed
        let drifted = !isLive && abs(elapsed - expected) > 2
        guard snapshot != published || !cardIsOurs || drifted else { return }
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
            MPNowPlayingInfoPropertyExternalContentIdentifier: Self.identifierPrefix + snapshot.identity,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.isPlaying ? snapshot.rate : 0.0,
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
        let center = commandCenter
        // A book's chapters run far too long to move through by track: the
        // card's buttons skip back and forward instead, which it draws only
        // while the track commands are off.
        Self.set(center.nextTrackCommand, enabled: snapshot.canSkip && !snapshot.isBook)
        Self.set(center.previousTrackCommand, enabled: !snapshot.isLive && !snapshot.isBook)
        Self.set(center.skipForwardCommand, enabled: snapshot.isBook)
        Self.set(center.skipBackwardCommand, enabled: snapshot.isBook)
        Self.set(center.changePlaybackRateCommand, enabled: snapshot.isBook)
        Self.set(center.changePlaybackPositionCommand, enabled: !snapshot.isLive && snapshot.duration > 0)
        Self.set(center.stopCommand, enabled: snapshot.isLive)
        // The Sonos mirror switches these off for its card; this card is
        // back, and so are they — bar a station's, which has neither.
        // A book has neither: its files are its chapters, in order, once.
        Self.set(center.changeShuffleModeCommand, enabled: !snapshot.isLive && !snapshot.isBook)
        Self.set(center.changeRepeatModeCommand, enabled: !snapshot.isLive && !snapshot.isBook)

        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = snapshot.isPlaying ? .playing : .paused

        // A new song, for lining up with what the car showed
        // (`Scripts/carplay-nowplaying-log.sh`); not each pause or drift.
        if published?.identity != snapshot.identity {
            let kind = snapshot.isLive ? "live" : snapshot.isBook ? "book" : "song"
            let state = snapshot.isPlaying ? "playing" : "paused"
            let replaced = published.map { ", in place of \($0.title)" } ?? ""
            Self.log.notice("card up: \(snapshot.title, privacy: .public) (\(kind, privacy: .public)), \(state, privacy: .public)\(replaced, privacy: .public)")
        }
        published = snapshot
        publishedElapsed = max(0, elapsed)
        publishedAt = .now
        if snapshot.isLive {
            Self.log.debug("live card: \(snapshot.title, privacy: .public) on \(snapshot.album, privacy: .public), \(snapshot.isPlaying ? "playing" : "paused", privacy: .public)")
        }

        if publishedArtworkURL != snapshot.artworkURL {
            loadArtwork(from: snapshot.artworkURL, item: item)
        }
    }

    private func isOurs(_ info: [String: Any]?) -> Bool {
        (info?[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String)?.hasPrefix(Self.identifierPrefix) ?? false
    }

    /// Sets a command's state only when it changes, so a republish (a new
    /// song, a pause) isn't also a round of command updates for the system
    /// to pass on to a car.
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
            infoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] = nil
            return
        }
        // A book's file shows its Audible edition's cover, as the player
        // does (`ContentArtworkView.drawnContent(for:)`).
        let drawn = item.map(ContentArtworkView.drawnContent(for:))
        let drawnURL = drawn.flatMap { $0.id == item?.id ? nil : $0.artwork ?? $0.thumbnail } ?? url
        var request = drawn.map {
            ContentArtworkView.artworkRequest(for: $0, url: drawnURL, preferredSize: ContentArtworkView.playerPreferredSize)
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
        if isOurs(infoCenter.nowPlayingInfo) {
            infoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
        }
    }

    // MARK: - Remote commands

    /// Handlers arrive on the main thread, hence `assumeIsolated`. Only this
    /// presenter's targets are removed on the way out, so the Sonos mirror's
    /// handlers, if any are registered, are left alone.
    private func registerCommands() {
        let center = commandCenter
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
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: AudiobookPlayer.skipForwardInterval)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: AudiobookPlayer.skipBackInterval)]
        center.changePlaybackRateCommand.supportedPlaybackRates = AudiobookPlayer.rates.map { NSNumber(value: $0) }

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
        // A book's skips go through the book, across its files.
        add(center.skipForwardCommand) { _, event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? AudiobookPlayer.skipForwardInterval
            Task { await AudiobookPlayer.shared.skip(by: interval) }
            return .success
        }
        add(center.skipBackwardCommand) { _, event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? AudiobookPlayer.skipBackInterval
            Task { await AudiobookPlayer.shared.skip(by: -interval) }
            return .success
        }
        add(center.changePlaybackRateCommand) { _, event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            AudiobookPlayer.shared.setRate(Double(event.playbackRate))
            return .success
        }
        // A car's shuffle and repeat buttons (`CarPlayInterface`) take a tap
        // only while these commands are there to take one: without them the
        // buttons drew but did nothing. Siri and accessories send them as
        // they are. A station has neither.
        add(center.changeShuffleModeCommand) { player, event in
            guard let event = event as? MPChangeShuffleModeCommandEvent, !player.isPlayingStation, !player.isOnBookFile else { return .commandFailed }
            player.setShuffle(event.shuffleType != .off)
            return .success
        }
        add(center.changeRepeatModeCommand) { player, event in
            guard let event = event as? MPChangeRepeatModeCommandEvent, !player.isPlayingStation, !player.isOnBookFile else { return .commandFailed }
            player.setRepeatMode(LocalPlaybackService.RepeatMode(event.repeatType))
            return .success
        }
    }

    private func unregisterCommands() {
        for (command, token) in commandTokens {
            command.removeTarget(token)
        }
        commandTokens = []
        // Nothing else takes these; left on, they would outlive the card.
        // Only a live card has stop, only a book's the skips and the rate.
        let center = commandCenter
        center.stopCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changePlaybackRateCommand.isEnabled = false
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
