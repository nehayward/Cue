import Foundation
import AVFoundation
import Observation

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
    public static var shared = AudioPlaybackService()

    // MARK: - Public Properties
    var currentTrack: URL?
    var playbackState: PlaybackState = .idle
    var playbackProgress: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Float = 1.0 {
        didSet {
            audioPlayer?.volume = volume
        }
    }

    /// Set when audio was started via `preview(url:)`. Guards `stopPreview()`
    /// so it never cuts off real Sonos-triggered playback.
    private(set) var isPreviewMode = false

    var isPlaying: Bool {
        playbackState == .playing
    }

    func isPreviewing(_ url: URL) -> Bool {
        currentTrack == url && isPreviewMode && (playbackState == .loading || playbackState == .playing)
    }

    // MARK: - Private Properties
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored private var progressObserver: Any?

    // MARK: - Initialization
    override init() {
        super.init()
    }

    // MARK: - Public Methods
    @MainActor
    public func play(
        url: URL,
        category: AVAudioSession.Category = .playback,
        options: AVAudioSession.CategoryOptions = [.duckOthers],
        isPreview: Bool = false
    ) async {
        stop()               // clears isPreviewMode to false
        isPreviewMode = isPreview  // re-set correctly after stop()

        currentTrack = url
        playbackState = .loading

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }
            try await playAudioData(data, category: category, options: options)
        } catch {
            guard !Task.isCancelled else { return }
            playbackState = .error(error.localizedDescription)
        }
    }

    /// Plays a short preview in a mixed ambient session so it layers over other
    /// audio. No-op if the same clip is already loading or playing.
    @MainActor
    public func preview(url: URL) async {
        guard !isPreviewing(url) else { return }
        await play(url: url, category: .ambient, options: [.mixWithOthers], isPreview: true)
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
        audioPlayer?.stop()
        audioPlayer = nil
        playbackState = .stopped
        playbackProgress = 0
        duration = 0
        currentTrack = nil
        isPreviewMode = false
        stopProgressObserver()
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print(error)
        }
    }

    @MainActor
    public func seek(to position: TimeInterval) {
        guard let audioPlayer = audioPlayer else { return }
        audioPlayer.currentTime = position
        playbackProgress = position
    }

    // MARK: - Private Methods
    @MainActor
    private func playAudioData(
        _ data: Data,
        category: AVAudioSession.Category = .playback,
        options: AVAudioSession.CategoryOptions = [.duckOthers]
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
        let displayLink = CADisplayLink(target: self, selector: #selector(updateProgress))
        displayLink.preferredFramesPerSecond = 30
        displayLink.add(to: .main, forMode: .common)
        progressObserver = displayLink
    }

    @MainActor
    @objc private func updateProgress() {
        guard let audioPlayer = audioPlayer, playbackState == .playing else { return }
        playbackProgress = audioPlayer.currentTime
    }

    private func stopProgressObserver() {
        if let displayLink = progressObserver as? CADisplayLink {
            displayLink.invalidate()
        }
        progressObserver = nil
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
