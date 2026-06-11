import SwiftUI
import SonosKit
import VibesDS
import SubscriptionKit

struct MiniPlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(SelectedGroupService.self) private var selectedGroupService
    @Environment(SubscriptionService.self) var subscriptionService
    @Environment(\.colorScheme) var colorScheme: ColorScheme

    private var selectedGroup: GroupRoom? {
        guard let groupID = selectedGroupService.group?.coordinatorID else {
            return nil
        }
        return sonosService.sorted.first(where: { $0.coordinatorID == groupID })
    }

    var body: some View {
#if !targetEnvironment(macCatalyst) && !os(visionOS)
        if selectedGroup != nil {
            VStack {
                if let group = selectedGroup {
                    VStack(spacing: 8) {
                        groupInfoButton(for: group)
                        TVControlsView(group: group)
                        VolumeControlView(group: group)
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .frame(height: 12)
                    }
                    .foregroundStyle(.primary)
                    .tint(.primary)
                }
            }
            .padding()
            .frame(maxWidth: 600)
            .background {
                if #available(iOS 26.0, *) {
                    Capsule()
                        .glassEffect(.regular.interactive())
                } else {
                    Capsule()
                        .foregroundStyle(.ultraThinMaterial)
                }
            }
            .padding(.horizontal, 8)
            .animation(.interactiveSpring.delay(0.3), value: selectedGroupService.group)
            .animation(.interactiveSpring, value: selectedGroupService.group?.coordinatorRoom.track)
        } else {
            EmptyView()
        }
#endif
    }

    private func groupInfoButton(for group: GroupRoom) -> some View {
        Button {
            HapticManager.shared.fireHaptic(.buttonPress)
            guard subscriptionService.subscription.isActive else {
                Router.main.fullScreenCover(to: .paywall)
                return
            }
            Router.main.inspectorSheet = nil
            Router.main.show(destination: .player(groupID: group.coordinatorID))
        } label: {
            HStack {
                artworkView(for: group)
                trackInfoView(for: group)
                Spacer()
                if group.coordinatorRoom.track != .empty {
                    playPauseButton(for: group)
                    nextTrackButton(for: group)
                }
            }
        }
    }

    private func artworkView(for group: GroupRoom) -> some View {
        ContentArtworkView(content: group.coordinatorRoom.track.toPlayable)
            .frame(width: 40, height: 40)
    }

    private func trackInfoView(for group: GroupRoom) -> some View {
        VStack(alignment: .leading) {
            Text(group.nameWithCount)
                .font(.caption2)
            MarqueeText([group.coordinatorRoom.track.song, group.coordinatorRoom.track.artist].filter{ !$0.isEmpty }.joined(separator: " • "))
                .transition(.slide)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fontDesign(.rounded)
        .lineLimit(1, reservesSpace: true)
    }

    private func playPauseButton(for group: GroupRoom) -> some View {
        Button {
            Task {
                HapticManager.shared.fireHaptic(.buttonPress)
                await sonosService.togglePlayPause(for: group)
            }
        } label: {
            playPauseLabel(for: group)
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.circle)
    }

    private func playPauseLabel(for group: GroupRoom) -> some View {
        PlaybackIconView(
            value: group.coordinatorRoom.playbackPosition,
            total: group.coordinatorRoom.track.duration,
            isPlaying: group.coordinatorRoom.isPlaying
        )
        .font(.title)
    }

    private func nextTrackButton(for group: GroupRoom) -> some View {
        Button {
            Task {
                HapticManager.shared.fireHaptic(.buttonPress)
                await sonosService.next(ip: group.ip)
                try? await sonosService.updateGroups(from: [group])
            }
        } label: {
            Image(systemName: "forward.fill")
                .padding(4)
        }
        .buttonBorderShape(.circle)
        .disabled(!group.availableActions.contains(.next))
    }
}

private struct TVControlsView: View {
    let group: GroupRoom

    var body: some View {
        let settings = group.tvSettings
        let nightMode = settings?.nightMode ?? false
        let dialogLevel = settings?.dialogLevel ?? false

        HStack(spacing: 16) {
            Button {
                guard let settings else { return }
                Task {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    try? await SonosService.shared.setNightMode(group.coordinatorRoom.ip, enabled: !settings.nightMode)
                    group.tvSettings = try await SonosService.shared.getTVSettings(ip: group.coordinatorRoom.ip)
                }
            } label: {
                Label("Night Mode", systemImage: "moon.zzz.fill")
                    .symbolRenderingMode(.hierarchical)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(nightMode ? .accent : .secondary.opacity(0.8))
            }
            .buttonStyle(.bordered)
            .tint(nightMode ? .accent : nil)
            .animation(.spring, value: nightMode)
            .disabled(settings == nil)

            MuteButton(group: group)

            Button {
                guard let settings else { return }
                Task {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    try? await SonosService.shared.setDialogLevel(group.coordinatorRoom.ip, enabled: !settings.dialogLevel)
                    group.tvSettings = try await SonosService.shared.getTVSettings(ip: group.coordinatorRoom.ip)
                }
            } label: {
                Label("Speech Enhancement", systemImage: "person.wave.2.fill")
                    .symbolRenderingMode(.hierarchical)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(dialogLevel ? .accent : .secondary.opacity(0.8))
            }
            .buttonStyle(.bordered)
            .tint(dialogLevel ? .accent : nil)
            .animation(.spring, value: dialogLevel)
            .disabled(settings == nil)
        }
        .opacity(group.TVMode ? 1 : 0)
        .animation(.easeInOut, value: group.TVMode)
    }
}

extension SonosService {
    func togglePlayPause(for group: GroupRoom) async {
        if group.coordinatorRoom.isPlaying {
            await pause(ip: group.coordinatorRoom.ip)
        } else {
            await play(ip: group.coordinatorRoom.ip)
        }
    }
}


extension View {
    @ViewBuilder
    func miniPlayerOnScrollHandler() -> some View {
        if #available(iOS 18.0, *) {
            self
//            self.onScrollGeometryChange(for: CGFloat.self, of: { geo in
//                return geo.contentOffset.y + geo.contentInsets.top
//            }, action: { new, old in
//                let delta = new - old
//                guard new >= 0 else { return }
//
//                withAnimation(.interactiveSpring()) {
//                    if delta < 0 {  // Scrolling up
//                        MiniPlayerManger.shared.offset = min(abs(new), 300)  // Show view
//                    } else if delta > 0 {  // Scrolling down
//                        MiniPlayerManger.shared.offset = 0    // Hide view
//                    }
//                }
//            })
        } else {
            self // fallback behavior for earlier versions
        }
    }
}
