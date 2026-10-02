import AVFoundation
import MediaPlayer
import Observation
import OSLog
import WatchKit
import WatchSync

/// Plays what's on the watch, to headphones or a speaker.
///
/// A long-form audio session: the system offers its route picker when
/// nothing's connected, playback carries on with the screen off, and the
/// song shows in Now Playing, where the Digital Crown sets the volume. Only
/// songs that are here play; a queue is the downloaded songs of an album,
/// playlist, artist or the Songs list.
@MainActor
@Observable
final class WatchPlayer {
    static let shared = WatchPlayer()

    private(set) var queue: [WatchTrack] = []
    private(set) var index = 0
    private(set) var isPlaying = false

    var current: WatchTrack? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var commandsConfigured = false
    @ObservationIgnored private let logger = Logger(subsystem: "dance.cue.watch", category: "Player")

    private init() {
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in
                self?.isPlaying = playing
                self?.updateNowPlaying()
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            Task { @MainActor in
                guard let self, item != nil, item === self.player.currentItem else { return }
                self.next()
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

    /// Plays these songs — those of them that are here — from the one with
    /// `key`, or shuffled with that one first.
    func play(_ tracks: [WatchTrack], startingAt key: String? = nil, shuffled: Bool = false) {
        let store = WatchDownloadStore.shared
        var playable = tracks.filter { store.localURL(for: $0) != nil }
        guard !playable.isEmpty else { return }
        var start = 0
        if shuffled {
            playable.shuffle()
            if let key, let found = playable.firstIndex(where: { $0.key == key }) {
                playable.swapAt(0, found)
            }
        } else if let key, let found = playable.firstIndex(where: { $0.key == key }) {
            start = found
        }
        queue = playable
        index = start
        Task { await startPlayback() }
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

    private func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        queue = []
        index = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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

    /// Loads the song at `index` — or the next one that's still here, when
    /// it was removed from the watch since the queue was made.
    private func loadCurrent() {
        let store = WatchDownloadStore.shared
        while let track = current {
            if let url = store.localURL(for: track) {
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                updateNowPlaying()
                return
            }
            queue.remove(at: index)
        }
        stop()
    }

    private func updateNowPlaying() {
        guard let track = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let elapsed = player.currentTime().seconds
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed.isFinite ? elapsed : 0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let album = track.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let duration = track.duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
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
