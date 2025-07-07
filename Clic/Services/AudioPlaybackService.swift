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
    
    var isPlaying: Bool {
        playbackState == .playing
    }
    
    // MARK: - Private Properties
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored private var progressObserver: Any?
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupAudioSession()
    }
    
    // MARK: - Public Methods
    @MainActor
    public func play(url: URL) async {
        // Stop any currently playing audio
        stop()
        
        currentTrack = url
        playbackState = .loading
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try await playAudioData(data)
        } catch {
            playbackState = .error(error.localizedDescription)
        }
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
        stopProgressObserver()
    }
    
    @MainActor
    public func seek(to position: TimeInterval) {
        guard let audioPlayer = audioPlayer else { return }
        audioPlayer.currentTime = position
        playbackProgress = position
    }
    
    // MARK: - Private Methods
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    
    @MainActor
    private func playAudioData(_ data: Data) async throws {
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
        
        // Use CADisplayLink for smoother progress updates tied to display refresh
        // Higher frequency for smoother animations, especially during scrubbing
        let displayLink = CADisplayLink(target: self, selector: #selector(updateProgress))
        displayLink.preferredFramesPerSecond = 30 // Update 30 times per second for smooth UI
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
            stopProgressObserver()
        }
    }
    
    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            playbackState = .error(error?.localizedDescription ?? "Decode error occurred")
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
