import SwiftUI
import AVFoundation

struct AudioPlaybackServicePreview: View {
    @Environment(AudioPlaybackService.self) private var audioService
    @State private var isScrubbing = false
    @State private var scrubbingProgress: Double = 0
    
    private let previewURL = URL(string: "https://p.scdn.co/mp3-preview/e4f2ca20fc8aea1eb592d613d7a4b4da6012eaa2?cid=9b377073ea334637b1406f329ce005de")!
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Audio Playback Service")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("MP3 Preview Demo")
                .font(.headline)
                .foregroundColor(.secondary)
            
            // Current Track Info
            VStack(spacing: 8) {
                Text("Current Track:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let currentTrack = audioService.currentTrack {
                    Text(currentTrack.absoluteString)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                } else {
                    Text("No track loaded")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            // Playback State
            VStack(spacing: 8) {
                Text("Playback State:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    stateIcon
                    Text(stateText)
                        .font(.body)
                        .fontWeight(.medium)
                }
            }
            
            
            // Progress Section
            VStack(spacing: 12) {
                Text("Progress")
                    .font(.headline)
                
                // Custom Progress Bar with Scrubbing
                VStack(spacing: 8) {
                    // Time Labels
                    HStack {
                        Text(formatTime(displayedProgress))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        
                        Spacer()
                        
                        Text(formatTime(audioService.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    
                    // Custom Scrubbing Slider
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background Track
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(height: 4)
                                .cornerRadius(2)
                            
                            // Progress Track
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: geometry.size.width * displayedProgressValue, height: 4)
                                .cornerRadius(2)
                                .animation(.linear(duration: isScrubbing ? 0 : 0.1), value: displayedProgressValue)
                            
                            // Scrubbing Thumb
                            Circle()
                                .fill(Color.blue)
                                .frame(width: isScrubbing ? 16 : 12, height: isScrubbing ? 16 : 12)
                                .offset(x: (geometry.size.width * displayedProgressValue) - (isScrubbing ? 8 : 6))
                                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isScrubbing)
                                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !isScrubbing {
                                        isScrubbing = true
                                        // Provide haptic feedback when starting scrub
                                        let impact = UIImpactFeedbackGenerator(style: .medium)
                                        impact.impactOccurred()
                                    }
                                    
                                    let progress = max(0, min(1, value.location.x / geometry.size.width))
                                    scrubbingProgress = progress
                                    
                                    // Light haptic feedback during scrub
                                    if abs(progress - scrubbingProgress) > 0.05 {
                                        let impact = UIImpactFeedbackGenerator(style: .light)
                                        impact.impactOccurred()
                                    }
                                }
                                .onEnded { value in
                                    let progress = max(0, min(1, value.location.x / geometry.size.width))
                                    let seekTime = progress * audioService.duration
                                    audioService.seek(to: seekTime)
                                    
                                    // End scrubbing after a short delay to allow smooth transition
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        isScrubbing = false
                                    }
                                    
                                    // Final haptic feedback
                                    let impact = UIImpactFeedbackGenerator(style: .medium)
                                    impact.impactOccurred()
                                }
                        )
                    }
                    .frame(height: 20)
                    
                    // Scrubbing Status
                    if isScrubbing {
                        Text("Scrubbing: \(formatTime(scrubbingProgress * audioService.duration))")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .transition(.opacity)
                    }
                }
                
                // Alternative: Standard Slider for comparison
                VStack(spacing: 4) {
                    Text("Standard Slider")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Slider(
                        value: Binding(
                            get: { isScrubbing ? scrubbingProgress : progressValue },
                            set: { newValue in
                                isScrubbing = true
                                scrubbingProgress = newValue
                            }
                        ),
                        in: 0...1,
                        onEditingChanged: { editing in
                            if !editing {
                                // User finished scrubbing
                                let seekTime = scrubbingProgress * audioService.duration
                                audioService.seek(to: seekTime)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    isScrubbing = false
                                }
                            }
                        }
                    )
                    .tint(.blue)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            
            // Volume Control
            VStack(spacing: 8) {
                Text("Volume")
                    .font(.headline)
                
                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundColor(.secondary)
                    
                    Slider(value: Binding(
                        get: { Double(audioService.volume) },
                        set: { audioService.volume = Float($0) }
                    ), in: 0...1)
                    
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(.secondary)
                }
            }
            
            // Control Buttons
            VStack(spacing: 16) {
                // Load/Play Button
                Button(action: {
                    Task {
                        await audioService.play(url: previewURL)
                    }
                }) {
                    HStack {
                        Image(systemName: "play.circle.fill")
                        Text("Load & Play Preview")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .disabled(audioService.playbackState == .loading)
                
                // Playback Controls
                HStack(spacing: 20) {
                    Button(action: {
                        audioService.stop()
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                    .disabled(audioService.playbackState == .idle || audioService.playbackState == .loading)
                    
                    Button(action: {
                        if audioService.isPlaying {
                            audioService.pause()
                        } else {
                            audioService.resume()
                        }
                    }) {
                        Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .disabled(audioService.playbackState == .idle || audioService.playbackState == .loading)
                    
                    Button(action: {
                        let newPosition = max(0, audioService.playbackProgress - 10)
                        audioService.seek(to: newPosition)
                    }) {
                        Image(systemName: "gobackward.10")
                            .font(.title2)
                            .foregroundColor(.orange)
                    }
                    .disabled(audioService.playbackState == .idle || audioService.playbackState == .loading)
                    
                    Button(action: {
                        let newPosition = min(audioService.duration, audioService.playbackProgress + 10)
                        audioService.seek(to: newPosition)
                    }) {
                        Image(systemName: "goforward.10")
                            .font(.title2)
                            .foregroundColor(.orange)
                    }
                    .disabled(audioService.playbackState == .idle || audioService.playbackState == .loading)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Audio Service Demo")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Computed Properties
    
    private var progressValue: Double {
        guard audioService.duration > 0 else { return 0 }
        return audioService.playbackProgress / audioService.duration
    }
    
    private var displayedProgressValue: Double {
        return isScrubbing ? scrubbingProgress : progressValue
    }
    
    private var displayedProgress: TimeInterval {
        return isScrubbing ? (scrubbingProgress * audioService.duration) : audioService.playbackProgress
    }
    
    private var stateIcon: some View {
        Group {
            switch audioService.playbackState {
            case .idle:
                Image(systemName: "moon.zzz")
                    .foregroundColor(.gray)
            case .loading:
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.blue)
            case .playing:
                Image(systemName: "play.circle.fill")
                    .foregroundColor(.green)
            case .paused:
                Image(systemName: "pause.circle.fill")
                    .foregroundColor(.orange)
            case .stopped:
                Image(systemName: "stop.circle.fill")
                    .foregroundColor(.red)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            }
        }
    }
    
    private var stateText: String {
        switch audioService.playbackState {
        case .idle:
            return "Idle"
        case .loading:
            return "Loading..."
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        case .stopped:
            return "Stopped"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    
    // MARK: - Helper Methods
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Preview Provider
#Preview {
    NavigationView {
        AudioPlaybackServicePreview()
    }
    .environment(AudioPlaybackService.shared)
}