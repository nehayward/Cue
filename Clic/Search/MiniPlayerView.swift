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
        VStack {
            if let group = selectedGroup {
                VStack(spacing: 8) {
                    groupInfoButton(for: group)
                    VolumeControlView(group: group)
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                }
                .onChange(of: selectedGroupService.group?.coordinatorRoom.track) {
                    MiniPlayerManger.shared.offset = 0
                }
                .foregroundStyle(.primary)
                .tint(.primary)
            }
        }
        .padding([.top, .horizontal])
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 4, bottomLeading: 0, bottomTrailing: 0, topTrailing: 4))
                .foregroundStyle(.ultraThinMaterial)
                .ignoresSafeArea(.all)
        }
        .opacity(selectedGroup == nil ? 0 : 1)
        .animation(.interactiveSpring.delay(0.3), value: selectedGroupService.group)
        .animation(.interactiveSpring, value: selectedGroupService.group?.coordinatorRoom.track)
#endif
    }
    
    private func groupInfoButton(for group: GroupRoom) -> some View {
        Button {
            guard subscriptionService.subscription.isActive else {
                Router.main.sheet(to: .paywall)
                return
            }
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
            .frame(width: 50, height: 50)
    }
    
    private func trackInfoView(for group: GroupRoom) -> some View {
        VStack(alignment: .leading) {
            Text(group.nameWithCount)
                .foregroundStyle(.secondary)
                .font(.caption2)
            MarqueeText([group.coordinatorRoom.track.song, group.coordinatorRoom.track.artist].filter{ !$0.isEmpty }.joined(separator: " • "))
                .transition(.slide)
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
        ZStack {
            if group.coordinatorRoom.track.duration > 0 {
                VibeGaugeView(
                    value: group.coordinatorRoom.track.playbackPosition,
                    total: group.coordinatorRoom.track.duration,
                    color: group.coordinatorRoom.isPlaying ? .primary : .primary.opacity(0.7),
                    lineWidth: 2
                )
                .frame(width: 30, height: 30)
            }
            Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                .font(.body)
                .foregroundStyle(group.coordinatorRoom.isPlaying ? .primary : Color.primary.opacity(0.7))
                .contentTransition(.symbolEffect(.automatic))
        }
        .frame(width: 40, height: 40)
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
