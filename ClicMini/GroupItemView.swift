import SwiftUI
import SonosKitMini
import Kingfisher

struct GroupItemView: View {
    @Binding var isVisible: Bool
    @Binding var device: SonosDevice
    @State private var hovered: Bool = false
    @State private var metadataTask: Task<Void, Never>? = nil
    @State private var showing: Bool = false
    @State private var updateTrigger = false
    @State private var timer: Timer?
    @State private var isTimerEnabled = true

    var body: some View {
        //        let _ = Self._printChanges()
        Section {
            deviceContent
        } header: {
            GroupHeader(device: device)
        }
    }
    
    private var deviceContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    HStack(spacing: 0) {
                        Link(destination: URL(string: "clic://device?id=\(device.id)")!) {
                            KFImage.url(device.track.sonosAlbumArtURL)
                                .placeholder {
                                    RoundedRectangle(cornerRadius: 4)
                                        .foregroundStyle(.thinMaterial)
                                }
                                .loadDiskFileSynchronously()
                                .diskCacheExpiration(.days(1))
                                .fade(duration: 0.2)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(alignment: .bottomTrailing) {
                                    device.musicServiceType.icon
                                        .frame(width: 12, height: 12)
                                }
                                .overlay {
                                    if device.groupIsMuted {
                                        Image(systemName: "speaker.slash.fill")
                                            .resizable()
                                            .scaledToFit()
                                            .foregroundStyle(.primary)
                                            .frame(width: 24, height: 24)
                                            .bold()
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                            .background {
                                                RoundedRectangle(cornerRadius: 2)
                                                    .foregroundStyle(.ultraThinMaterial)
                                            }
                                            .clipped()
                                            .transition(.opacity)
                                    }
                                }
                                .animation(.spring, value: device.groupIsMuted)
#if DEBUG && SCREENSHOT
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .foregroundStyle(.ultraThinMaterial)
                                }
#endif
                            
                            //                            if let trackInfo = device.currentTrackMetadata {
                            //                                VStack(alignment: .leading) {
                            //                                    MarqueeText(trackInfo.title)
                            //                                    Text(trackInfo.creator)
                            //                                        .foregroundStyle(.secondary)
                            //                                }
                            //                                .lineLimit(1, reservesSpace: true)
                            //                                .frame(maxWidth: .infinity, alignment: .leading)
                            //                            }
                            
                            VStack(alignment: .leading) {
                                if isVisible {
                                    MarqueeText(device.track.song)
                                        .transition(.identity)
                                } else {
                                    Text(device.track.song)
                                        .frame(maxWidth: .infinity)
                                        .transition(.identity)
                                }
                                Text(device.track.artist)
                                    .foregroundStyle(.secondary)
                                    .transaction { transaction in
                                        transaction.animation = nil
                                    }
                            }
                            .lineLimit(1, reservesSpace: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            playPauseButton(for: device)
                            nextTrackButton(for: device)
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: device.isPlaying)
                    }
                    .foregroundStyle(.primary)
                    .opacity(device.isTVMode ? 0 : 1)
                    
                    TVView(device: device)
                        .opacity(device.isTVMode ? 1 : 0)
                }
                
                VolumeControlView(device: $device)
                    .frame(height: 16)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .foregroundStyle(hovered ? Color(nsColor: .systemFill) : Color(nsColor: NSColor.secondarySystemFill))
            }
            .geometryGroup()
            .onHover { isHovered in
                hovered = isHovered
            }
        }
    }
    
    private func playPauseButton(for device: SonosDevice) -> some View {
        Button {
            Task {
                await SonosMiniService.shared.togglePlayback(ip: device.ip)
            }
        } label: {
            PlaybackIconView(value: device.progress, total: 1, isPlaying: device.isPlaying)
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .disabled(!device.availableActions.contains(.play))
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: device.isPlaying) {
            if device.isPlaying && isTimerEnabled {
                startTimer()
            } else {
                stopTimer()
            }
        }
        .id(updateTrigger) // Force view refresh when updateTrigger changes
    }
    
    /// Start the update timer
    private func startTimer() {
        guard timer == nil && isTimerEnabled else { return }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if device.isPlaying {
                updateTrigger.toggle()
            }
        }
    }
    
    /// Stop the update timer
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    /// Enable timer updates
    func enableTimer() {
        isTimerEnabled = true
        if device.isPlaying{
            startTimer()
        }
    }
    
    /// Disable timer updates
    func disableTimer() {
        isTimerEnabled = false
        stopTimer()
    }
    
    private func playPauseLabel(for device: SonosDevice) -> some View {
        Image(systemName: device.isPlaying ? "pause.fill" : "play.fill")
            .font(.body)
            .contentTransition(.symbolEffect(.automatic))
    }
    
    private func nextTrackButton(for device: SonosDevice) -> some View {
        Button {
            Task {
                await SonosMiniService.shared.next(ip: device.ip)
                try? await SonosMiniService.shared.updateWatchDevices(from: [device])
            }
        } label: {
            Image(systemName: "forward.fill")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!device.availableActions.contains(.next))
    }
}
