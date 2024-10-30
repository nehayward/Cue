import SwiftUI
import SonosKit
import VibesDS

struct MiniPlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(SelectedGroupService.self) private var selectedGroupService
    
    @State private var router = Router()
    
    var body: some View {
#if !targetEnvironment(macCatalyst)
        Group {
            if let group = selectedGroup {
                VStack(spacing: 8) {
                    groupInfoButton(for: group)
                    #if !targetEnvironment(macCatalyst)
                    VolumeControlView(group: .constant(group))
                    #endif
                }
                .transition(.push(from: .bottom).combined(with: .blurReplace))
                .onChange(of: selectedGroupService.group?.coordinatorRoom.track) {
                    MiniPlayerManger.shared.offset = 0
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .animation(.interactiveSpring.delay(0.3), value: selectedGroupService.group)
        .animation(.interactiveSpring, value: selectedGroupService.group?.coordinatorRoom.track)
#endif
    }
    
    private var selectedGroup: GroupRoom? {
        guard let groupID = selectedGroupService.group?.coordinatorID,
              let group = sonosService.sorted.first(where: { $0.coordinatorID == groupID })
        else { return nil }
        return group
    }
    
    private func groupInfoButton(for group: GroupRoom) -> some View {
        Button {
            Router.main.sheet(to: nil)
            if Router.main.path.last == .player(groupID: group.coordinatorID) {
                return
            } else {
                Router.main.path.removeAll()
                Router.main.navigate(to: .player(groupID: group.coordinatorID))
            }
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
                .font(.caption)
                .foregroundStyle(.secondary)
            Text([group.coordinatorRoom.track.song, group.coordinatorRoom.track.artist].filter{ !$0.isEmpty }.joined(separator: " • "))
                .transition(.slide)
        }
        .fontDesign(.rounded)
        .lineLimit(1, reservesSpace: true)
        .foregroundStyle(.primary)
        .tint(.primary)
        .transition(.slide)
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
                    color: group.coordinatorRoom.isPlaying ? .accent : .accent.opacity(0.7),
                    lineWidth: 2
                )
                .frame(width: 30, height: 30)
            }
            Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                .font(.body)
                .foregroundStyle(group.coordinatorRoom.isPlaying ? .accent : .accent.opacity(0.7))
                .contentTransition(.symbolEffect(.automatic))
        }
        .frame(width: 40, height: 40)
    }
    
    private func nextTrackButton(for group: GroupRoom) -> some View {
        Button {
            Task {
                HapticManager.shared.fireHaptic(.buttonPress)
                await sonosService.next(ip: group.ip)
            }
        } label: {
            Image(systemName: "forward.fill")
                .padding(4)
        }
        .buttonBorderShape(.circle)
        .disabled(!group.availableActions.contains(.next))
    }
    
    private var selectGroupButton: some View {
        Button {
            router.presentedSheet = .selectGroup(selectedGroupService: selectedGroupService)
        } label: {
            Text("Select Group")
        }
        .buttonStyle(.bordered)
        .tint(.accent)
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
            self.onScrollGeometryChange(for: CGFloat.self, of: { geo in
                return geo.contentOffset.y + geo.contentInsets.top
            }, action: { new, old in
                let delta = new - old
                guard new >= 0 else { return }
                
                withAnimation(.interactiveSpring()) {
                    if delta < 0 {  // Scrolling up
                        MiniPlayerManger.shared.offset = 300  // Show view
                    } else if delta > 0 {  // Scrolling down
                        MiniPlayerManger.shared.offset = 0    // Hide view
                    }
                }
            })
        } else {
            self // fallback behavior for earlier versions
        }
    }
}
