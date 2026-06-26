import Foundation
import AVFoundation
import Observation
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case error(String)
}


@Observable
public final class AudioPlaybackService: NSObject, @unchecked Sendable {
    public static let shared = AudioPlaybackService()

    // MARK: - Public Properties
    var currentTrack: URL?
    var playbackState: PlaybackState = .idle
    var playbackProgress: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Float = 1.0 {
        didSet {
            audioPlayer?.volume = volume
            streamPlayer?.volume = volume
        }
    }

    /// Set when audio was started via `preview(url:)`. Guards `stopPreview()`
    /// so it never cuts off real Sonos-triggered playback.
    private(set) var isPreviewMode = false

    @ObservationIgnored private var previewTask: Task<Void, Never>?

    var isPlaying: Bool {
        playbackState == .playing
    }

    func isPreviewing(_ url: URL) -> Bool {
        currentTrack == url && isPreviewMode && (playbackState == .loading || playbackState == .playing)
    }

    // MARK: - Private Properties
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var backgroundObserver: NSObjectProtocol?

    // Streaming path (used for sources without a short preview clip, e.g. Plex,
    // where the only audio is the full track served from the user's server).
    // AVPlayer streams progressively instead of downloading the whole file first.
    @ObservationIgnored private var streamPlayer: AVPlayer?
    @ObservationIgnored private var streamTimeObserver: Any?
    @ObservationIgnored private var streamEndObserver: NSObjectProtocol?
    @ObservationIgnored private var streamStatusObservation: NSKeyValueObservation?
    /// Bumped on every new stream so stale observer callbacks can be ignored
    /// without capturing the (non-Sendable) player/item into their closures.
    @ObservationIgnored private var streamSession = 0

    // MARK: - Initialization
    override init() {
        super.init()
        observeAppBackgrounding()
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    /// Stops any in-flight preview when the app is backgrounded. With the
    /// `.playback` session a clip would otherwise keep playing off-screen, so we
    /// cut it here. `stopPreview()` is guarded to preview mode, so this never
    /// touches real Sonos-triggered audio.
    private func observeAppBackgrounding() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stopPreview() }
        }
        #endif
    }

    // MARK: - Public Methods
    @MainActor
    public func play(
        url: URL,
        category: AVAudioSession.Category = .playback,
        options: AVAudioSession.CategoryOptions = [.duckOthers],
        isPreview: Bool = false
    ) async {
        // Tear down any existing audio WITHOUT cancelling previewTask — this
        // runs inside previewTask, so cancelling here would cancel ourselves.
        teardownAudio()
        isPreviewMode = isPreview  // re-set correctly after teardown

        currentTrack = url
        playbackState = .loading

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Superseded by a newer preview or an explicit stop — that caller
            // owns the resulting state, so just bail without touching it.
            guard !Task.isCancelled else { return }
            try await playAudioData(data, category: category, options: options)
        } catch {
            guard !Task.isCancelled else { return }
            playbackState = .error(error.localizedDescription)
        }
    }

    /// Plays a preview using the `.playback` session so it is audible even when
    /// the device's silent/mute switch is on — a preview is always an explicit
    /// user tap, so honoring that intent matters more than respecting silent mode
    /// (this also matches Apple Music's own preview behavior). An explicit call
    /// always (re)starts from the beginning — even if the same URL is already
    /// previewing — so the user can replay it. Manages its own Task internally —
    /// call sites do not need `Task { await ... }`.
    ///
    /// Pass `streaming: true` for sources that have no short preview clip and
    /// instead serve the full track (e.g. Plex). Those stream progressively via
    /// `AVPlayer` rather than downloading the whole file before playback.
    @MainActor
    public func preview(url: URL, streaming: Bool = false) {
        previewTask?.cancel()
        previewTask = Task { @MainActor in
            if streaming {
                playStream(url: url, category: .playback, options: [.duckOthers])
            } else {
                await play(url: url, category: .playback, options: [.duckOthers], isPreview: true)
            }
        }
    }

    /// Stops playback only when we're in preview mode — will not interrupt
    /// any other audio the app may be managing.
    @MainActor
    public func stopPreview() {
        guard isPreviewMode else { return }
        stop()
    }

    @MainActor
    public func pause() {
        guard let audioPlayer = audioPlayer, audioPlayer.isPlaying else { return }
        audioPlayer.pause()
        playbackState = .paused
        stopProgressObserver()
    }

    @MainActor
    public func resume() {
        guard let audioPlayer = audioPlayer, playbackState == .paused else { return }
        audioPlayer.play()
        playbackState = .playing
        startProgressObserver()
    }

    @MainActor
    public func stop() {
        // Cancel the in-flight preview load so it doesn't resume into playback
        // after the user asked to stop, then tear down audio + state.
        previewTask?.cancel()
        previewTask = nil
        teardownAudio()
    }

    /// Tears down the player and resets playback state. Does NOT cancel
    /// previewTask, so it is safe to call from inside that task (via `play`).
    @MainActor
    private func teardownAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        teardownStream()
        playbackState = .stopped
        playbackProgress = 0
        duration = 0
        currentTrack = nil
        isPreviewMode = false
        stopProgressObserver()
        do {
            // Notify others so any audio we ducked returns to full volume.
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print(error)
        }
    }

    /// Tears down the streaming player and its observers. Separate from
    /// `teardownAudio` only so the setup code reads clearly; always called via it.
    @MainActor
    private func teardownStream() {
        streamSession += 1  // invalidate any in-flight observer callbacks
        streamPlayer?.pause()
        if let streamTimeObserver {
            streamPlayer?.removeTimeObserver(streamTimeObserver)
        }
        streamTimeObserver = nil
        if let streamEndObserver {
            NotificationCenter.default.removeObserver(streamEndObserver)
        }
        streamEndObserver = nil
        streamStatusObservation?.invalidate()
        streamStatusObservation = nil
        streamPlayer = nil
    }

    @MainActor
    public func seek(to position: TimeInterval) {
        guard let audioPlayer = audioPlayer else { return }
        audioPlayer.currentTime = position
        playbackProgress = position
    }

    // MARK: - Private Methods

    /// Streams a track progressively with `AVPlayer`. Used for preview sources
    /// that serve the full file (e.g. Plex) so playback starts without first
    /// downloading the whole track into memory. Drives the same observable state
    /// (`playbackState`, `duration`, `playbackProgress`) as the clip path, so the
    /// preview UI behaves identically. Streaming is always preview mode.
    @MainActor
    private func playStream(
        url: URL,
        category: AVAudioSession.Category,
        options: AVAudioSession.CategoryOptions
    ) {
        teardownAudio()
        isPreviewMode = true  // re-set correctly after teardown
        currentTrack = url
        playbackState = .loading
        streamSession += 1
        let session = streamSession

        do {
            try AVAudioSession.sharedInstance().setCategory(category, mode: .default, options: options)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            playbackState = .error(error.localizedDescription)
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = volume
        streamPlayer = player

        // Flip to .playing and capture the real duration once the item is ready.
        // Read the values off the item here, then hop to the main actor with only
        // Sendable values (status/Double/String) — never the item itself.
        streamStatusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            let status = observedItem.status
            let seconds = observedItem.duration.seconds
            let errorDescription = observedItem.error?.localizedDescription
            Task { @MainActor in
                guard let self, self.streamSession == session else { return }
                switch status {
                case .readyToPlay:
                    if seconds.isFinite, seconds > 0 { self.duration = seconds }
                    self.playbackState = .playing
                case .failed:
                    self.playbackState = .error(errorDescription ?? "Streaming failed")
                default:
                    break
                }
            }
        }

        // Drive the progress bar a few times a second.
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        streamTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in
                guard let self, self.streamSession == session else { return }
                self.playbackProgress = seconds
            }
        }

        streamEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stopPreview() }
        }

        player.play()
    }

    @MainActor
    private func playAudioData(
        _ data: Data,
        category: AVAudioSession.Category,
        options: AVAudioSession.CategoryOptions
    ) async throws {
        try AVAudioSession.sharedInstance().setCategory(category, mode: .default, options: options)
        try AVAudioSession.sharedInstance().setActive(true)
        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.delegate = self
        audioPlayer?.volume = volume
        audioPlayer?.prepareToPlay()

        duration = audioPlayer?.duration ?? 0

        guard let audioPlayer = audioPlayer else {
            throw AudioPlaybackError.playerInitializationFailed
        }

        if audioPlayer.play() {
            playbackState = .playing
            startProgressObserver()
        } else {
            throw AudioPlaybackError.playbackFailed
        }
    }

    @MainActor
    private func startProgressObserver() {
        stopProgressObserver()
        let link = CADisplayLink(target: self, selector: #selector(updateProgress))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @MainActor
    @objc private func updateProgress() {
        guard let audioPlayer = audioPlayer, playbackState == .playing else { return }
        playbackProgress = audioPlayer.currentTime
    }

    @MainActor
    private func stopProgressObserver() {
        displayLink?.invalidate()
        displayLink = nil
    }
}

// MARK: - AVAudioPlayerDelegate
extension AudioPlaybackService: AVAudioPlayerDelegate {
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if flag {
                playbackState = .stopped
                playbackProgress = 0
            } else {
                playbackState = .error("Playback finished unsuccessfully")
            }
            isPreviewMode = false
            stopProgressObserver()
        }
    }

    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            playbackState = .error(error?.localizedDescription ?? "Decode error occurred")
            isPreviewMode = false
            stopProgressObserver()
        }
    }
}

// MARK: - Error Types
enum AudioPlaybackError: LocalizedError {
    case playerInitializationFailed
    case playbackFailed
    case invalidURL
    case networkError

    var errorDescription: String? {
        switch self {
        case .playerInitializationFailed:
            return "Failed to initialize audio player"
        case .playbackFailed:
            return "Failed to start playback"
        case .invalidURL:
            return "Invalid audio URL"
        case .networkError:
            return "Failed to load audio file"
        }
    }
}
