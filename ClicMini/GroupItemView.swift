import SwiftUI
import SonosKitMini
import Kingfisher

struct GroupItemView: View {
    @Binding var isVisible: Bool
    @Binding var device: SonosDevice
    @Binding var expandedGroupIDs: Set<String>
    @State private var hovered: Bool = false
    @State private var showing: Bool = false
    @State private var miniSettingsService = MiniSettingsService.shared
    @State private var sonosServiceMini = SonosMiniService.shared
    @State private var isHovering: Bool = false

    private var showSpeakerVolumes: Bool {
        expandedGroupIDs.contains(device.id)
    }

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
                            KFImage.url(device.track.sonosAlbumArtURL, cacheKey: device.track.album)
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
                                                RoundedRectangle(cornerRadius: 4)
                                                    .foregroundStyle(.ultraThinMaterial)
                                            }
                                            .clipped()
                                            .transition(.opacity)
                                    }
                                }
                                .animation(.spring, value: device.groupIsMuted)
                                .overlay {
                                    if isHovering {
                                        RoundedRectangle(cornerRadius: 4)
                                            .foregroundStyle(.ultraThinMaterial)
                                            .overlay {
                                                ZStack {
                                                    Circle()
                                                        .stroke(.secondary.opacity(0.4),lineWidth: 2)
                                                    if device.queueTotal > 0 && device.track.position > 0 {
                                                        Circle()
                                                            .trim(from: 0, to: CGFloat(min(Double(device.track.position) / Double(device.queueTotal), 1.0)))
                                                            .stroke(
                                                                .primary,
                                                                style: StrokeStyle(
                                                                    lineWidth: 2,
                                                                    lineCap: .round
                                                                )
                                                            )
                                                            .rotationEffect(.degrees(-90))
                                                    }
                                                }
                                                .overlay {
                                                    Text("\(device.queueTotal)")
                                                        .lineLimit(1)
                                                        .minimumScaleFactor(0.5)
                                                        .padding(.horizontal, 4)
                                                        .allowsTightening(true)
                                                        .contentTransition(.numericText())
                                                        .font(.caption.monospacedDigit())
                                                }
                                                .fontDesign(.rounded)
                                                .frame(width: 30, height: 30)
                                                .accessibilityLabel("Queue")
                                            }
                                    }
                                }
                                .onHover { isHovering in
                                    self.isHovering = isHovering
                                }
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
                                // Both branches must lay out identically: the swap
                                // happens the instant the panel opens (isVisible flips
                                // in GroupMenuScreen.onAppear), so any difference in
                                // alignment reads as the title sliding across the row.
                                // The transaction override keeps an ambient animation
                                // from an unrelated state change in the same update
                                // (e.g. isLoading) from animating that swap.
                                Group {
                                    if isVisible {
                                        MarqueeText(device.track.song)
                                    } else {
                                        Text(device.track.song)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.identity)
                                .transaction { transaction in
                                    transaction.animation = nil
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

                if !device.rooms.isEmpty {
                    Button {
                        withAnimation(.interactiveSpring) {
                            if expandedGroupIDs.contains(device.id) {
                                expandedGroupIDs.remove(device.id)
                            } else {
                                expandedGroupIDs.insert(device.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "hifispeaker.2.fill")
                                .font(.caption2)
                            Text("\(device.allDevices.count) speakers")
                                .font(.caption)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .rotationEffect(.degrees(showSpeakerVolumes ? 90 : 0))
                        }
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showSpeakerVolumes {
                        SpeakerVolumesView(device: device)
                            .geometryGroup()
                            .transition(.opacity)
                    }
                }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .foregroundStyle(hovered ? Color(nsColor: .systemFill) : Color(nsColor: NSColor.secondarySystemFill))
                    .overlay {
                        if miniSettingsService.isSpeakerPinned(id: device.id) {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.accent.opacity(0.5), lineWidth: 1.5)
                        }
                    }
            }
            .geometryGroup()
            .onHover { isHovered in
                hovered = isHovered
            }
            .contextMenu {
                groupingMenu
            }
        }
    }
    
    @ViewBuilder
    private var groupingMenu: some View {
        if device.allDevices.count > 1 {
            Button {
                Task {
                    await SonosMiniService.shared.ungroup(device: device)
                }
            } label: {
                Label("Ungroup", systemImage: "hifispeaker.badge.minus.fill")
                    .symbolVariant(.slash)
            }

            Divider()
        }

        Menu {
            ForEach(availableDevicesToGroup) { availableDevice in
                Button {
                    Task {
                        await SonosMiniService.shared.group(rooms: [availableDevice], to: device.id)
                    }
                } label: {
                    Text(availableDevice.name)
                }
            }
        } label: {
            Label("Group with…", systemImage: "hifispeaker.arrow.forward.fill")
        }
        .disabled(availableDevicesToGroup.isEmpty)
        
        if let quality = device.quality, !quality.sampleRateFormatted.isEmpty {
            let qualityString = [quality.bitDepth.map { "\($0)-bit" }, quality.sampleRateFormatted]
                .compactMap { $0 }
                .joined(separator: " • ")

            Button {
                
            } label: {
                Label(qualityString, systemImage: "waveform")
            }
        }
        
        Link(destination: URL(string: "clic://device?id=\(device.id)")!) {
            Label("Open in Clic…", systemImage: "arrow.up.forward")
        }
    }
    
    private var availableDevicesToGroup: [SonosDevice] {
        sonosServiceMini.sortedNowPlaying.filter { otherDevice in
            // Don't include the current device or devices already in this group
            otherDevice.id != device.id &&
            !device.allDevices.contains(where: { $0.id == otherDevice.id })
        }
    }
    
    private func playPauseButton(for device: SonosDevice) -> some View {
        Button {
            Task {
                await SonosMiniService.shared.togglePlayback(ip: device.ip)
            }
        } label: {
            // While playing, a periodic 1 Hz TimelineView re-renders just this
            // small icon so the extrapolated progress stays live. `.periodic` is
            // a plain timer schedule (no display link), and the view isn't even
            // mounted when idle, so nothing ticks for paused speakers. Unlike
            // the previous run-loop Timer + .id() approach — which rebuilt the
            // whole button's identity every second and was retained by the run
            // loop until invalidated — this is structured and tears down with
            // the row.
            Group {
                if device.isPlaying {
                    TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                        PlaybackIconView(value: device.progress, total: 1, isPlaying: device.isPlaying)
                    }
                } else {
                    PlaybackIconView(value: device.progress, total: 1, isPlaying: device.isPlaying)
                }
            }
            // The icon itself is only 24pt and its ring is a thin stroke, so
            // hit-testing the drawn shape alone left a tiny target. Match the
            // next button's 44pt area and make the whole square tappable — the
            // progress ring and the space around it now toggle playback.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!device.availableActions.contains(.play))
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
