import AVFoundation
import MediaPlayer
import Observation
import OSLog
import UIKit
import WatchKit
import WatchSync

/// Plays Plex and Subsonic songs on the watch, to headphones or a speaker.
///
/// A long-form audio session: the system offers its route picker when
/// nothing's connected, playback carries on with the screen off, and the
/// song shows in Now Playing, where the Digital Crown sets the volume. A
/// song that's downloaded plays from its file; any other streams from its
/// server (`streamQuality`), through the iPhone when it's connected over
/// Bluetooth and over the watch's own Wi‑Fi or cellular otherwise. A song
/// that won't stream (no network, the server's away) is skipped.
@MainActor
@Observable
final class WatchPlayer {
    static let shared = WatchPlayer()

    private(set) var queue: [WatchSong] = []
    private(set) var index = 0
    private(set) var isPlaying = false

    var current: WatchSong? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    /// Streams go as 128 kbps MP3: it keeps up through the iPhone's
    /// Bluetooth link (tens of KB/s), and the watch's player can't open the
    /// Opus in Ogg the servers send otherwise.
    static let streamQuality = WatchDownloadQuality.small
    /// A Plex client and session of the player's own, so a stream never
    /// ends a download's conversion (`WatchDownloadStore.plexClients`), even
    /// of the same song.
    private static let plexClient = "Cue-Watch-Player"
    private static let plexSession = "cue-watch-player"

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    /// The current item's, to skip a stream that won't open.
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var failureObserver: NSObjectProtocol?
    /// Songs that failed in a row; past a few, nothing's reachable and it
    /// stops rather than run down the queue.
    @ObservationIgnored private var failuresInARow = 0
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var commandsConfigured = false
    @ObservationIgnored private let logger = Logger(subsystem: "dance.cue.watch", category: "Player")

    private init() {
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            let started = player.timeControlStatus == .playing
            Task { @MainActor in
                if started {
                    self?.failuresInARow = 0
                }
                self?.isPlaying = playing
                self?.updateNowPlaying()
                WidgetStatePublisher.schedule()
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            Task { @MainActor in
                guard let self, item != nil, item === self.player.currentItem else { return }
                self.next()
            }
        }
        // A stream cut off part-way.
        failureObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor in
                guard let self, let item, item === self.player.currentItem else { return }
                self.skip(error: error)
            }
        }
        // A call or an alarm pauses the player by itself; carry on after
        // it when the system says to.
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let info = notification.userInfo
            let type = (info?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap { AVAudioSession.InterruptionType(rawValue: $0) }
            let options = (info?[AVAudioSessionInterruptionOptionKey] as? UInt).map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
            guard type == .ended, options.contains(.shouldResume) else { return }
            Task { @MainActor in
                self?.resume()
            }
        }
    }

    /// Plays these songs from the one with `key`, or shuffled with that one
    /// first: the downloaded ones from their files, the rest streamed.
    /// False when there are none.
    @discardableResult
    func play(_ songs: [WatchSong], startingAt key: String? = nil, shuffled: Bool = false) -> Bool {
        let (ordered, start) = Self.order(songs, startingAt: key, shuffled: shuffled)
        guard !ordered.isEmpty else { return false }
        queue = ordered
        index = start
        failuresInARow = 0
        Task { await startPlayback() }
        return true
    }

    /// `songs` in play order and where to start: as given from the one with
    /// `key`, or shuffled with that one first. Also how a play handed to the
    /// iPhone is ordered.
    static func order(_ songs: [WatchSong], startingAt key: String?, shuffled: Bool) -> (songs: [WatchSong], start: Int) {
        var songs = songs
        guard shuffled else {
            return (songs, key.flatMap { key in songs.firstIndex { $0.key == key } } ?? 0)
        }
        songs.shuffle()
        if let key, let found = songs.firstIndex(where: { $0.key == key }) {
            songs.swapAt(0, found)
        }
        return (songs, 0)
    }

    /// Everything downloaded to the watch, newest pick first: what plays
    /// with nothing in reach.
    @discardableResult
    func playDownloads(shuffled: Bool) -> Bool {
        let store = WatchDownloadStore.shared
        return play(downloaded(store.songs(in: store.picks.items.map(\.key))), shuffled: shuffled)
    }

    /// The downloaded songs of one album, playlist, artist or song on the
    /// watch.
    @discardableResult
    func play(pickKey: String, shuffled: Bool) -> Bool {
        play(downloaded(WatchDownloadStore.shared.songs(in: [pickKey])), shuffled: shuffled)
    }

    private func downloaded(_ songs: [WatchSong]) -> [WatchSong] {
        let store = WatchDownloadStore.shared
        return songs.filter { store.localURL(for: $0) != nil }
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        player.pause()
    }

    func resume() {
        guard current != nil else { return }
        if player.currentItem == nil {
            Task { await startPlayback() }
        } else {
            player.play()
        }
    }

    func next() {
        guard index + 1 < queue.count else {
            stop()
            return
        }
        index += 1
        loadCurrent()
        player.play()
    }

    /// Back to the start of the song, or to the one before when it's only
    /// just begun.
    func previous() {
        let elapsed = player.currentTime().seconds
        if index == 0 || (elapsed.isFinite && elapsed > 3) {
            player.seek(to: .zero)
            updateNowPlaying()
        } else {
            index -= 1
            loadCurrent()
            player.play()
        }
    }

    /// Ends playback and lets the audio session go: when what's playing
    /// moves to the iPhone, so Now Playing shows the iPhone's.
    func stop() {
        player.pause()
        itemObservation = nil
        player.replaceCurrentItem(with: nil)
        queue = []
        index = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        WidgetStatePublisher.schedule()
    }

    private func startPlayback() async {
        guard await activateSession() else { return }
        configureCommandsIfNeeded()
        loadCurrent()
        player.play()
    }

    /// Long-form audio, so the system routes it to headphones or a speaker
    /// — asking which, when none is connected. False when the person backed
    /// out of the picker or the session couldn't start.
    private func activateSession() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            return try await session.activate(options: [])
        } catch {
            logger.error("Couldn't start the audio session: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Loads the song at `index`: its file when it's downloaded, its stream
    /// otherwise.
    private func loadCurrent() {
        guard let song = current else {
            stop()
            return
        }
        let url: URL
        if let file = WatchDownloadStore.shared.localURL(for: song) {
            url = file
        } else {
            url = song.stream(at: Self.streamQuality, plexClient: Self.plexClient, plexSession: Self.plexSession).url
            logger.notice("Streaming \(song.key, privacy: .public)")
        }
        let item = AVPlayerItem(url: url)
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let error = item.error
            Task { @MainActor in
                guard let self, item === self.player.currentItem else { return }
                self.skip(error: error)
            }
        }
        player.replaceCurrentItem(with: item)
        updateNowPlaying()
        // A skip can keep playing straight through, so the widgets don't
        // hear of the new song from the play state.
        WidgetStatePublisher.schedule()
    }

    /// On to the next song when this one won't play — or stops, when
    /// several in a row haven't: nothing's reachable.
    private func skip(error: Error?) {
        failuresInARow += 1
        logger.error("Couldn't play \(self.current?.key ?? "-", privacy: .public): \(error?.localizedDescription ?? "unknown", privacy: .public)")
        if failuresInARow >= min(queue.count, 3) {
            stop()
        } else {
            next()
        }
    }

    private func updateNowPlaying() {
        guard let song = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let elapsed = player.currentTime().seconds
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed.isFinite ? elapsed : 0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let album = song.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let duration = song.duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let image = ArtworkStore.shared.image(for: song.artworkURL) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        } else if song.artworkURL != nil {
            // Not here yet: fetched, and put in once it is, if the song's
            // still playing.
            Task {
                guard await ArtworkStore.shared.fetch(song.artworkURL) != nil, current?.key == song.key else { return }
                updateNowPlaying()
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// The Now Playing controls, headphone buttons and the system's own
    /// player drive this one.
    private func configureCommandsIfNeeded() {
        guard !commandsConfigured else { return }
        commandsConfigured = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
    }
}
