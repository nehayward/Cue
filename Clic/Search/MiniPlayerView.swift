import SwiftUI
import SonosKit
import VibesDS

struct MiniPlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(SelectedGroupService.self) private var selectedGroupService
    
    @State private var router = Router()
    
    var body: some View {
        Group {
            if let group = selectedGroup {
                VStack(spacing: 8) {
                    groupInfoButton(for: group)
                    #if !targetEnvironment(macCatalyst)
                    VolumeControlView(group: .constant(group))
                    #endif
                }
                .transition(.push(from: .bottom).combined(with: .blurReplace))
            } else {
                selectGroupButton
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .animation(.bouncy.delay(0.2), value: selectedGroupService.group)
    }
    
    private var selectedGroup: GroupRoom? {
        guard let groupID = selectedGroupService.group?.coordinatorID,
              let group = sonosService.sorted.first(where: { $0.coordinatorID == groupID })
        else { return nil }
        return group
    }
    
    private func groupInfoButton(for group: GroupRoom) -> some View {
        Button {
            router.presentedSheet = .selectGroup(selectedGroupService: selectedGroupService)
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
            .animation(.bouncy, value: group.coordinatorRoom.track.trackID)
            .id(group.coordinatorRoom.track.id)
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
                    lineWidth: 4
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


struct CircularProgressView: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 2

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    color.opacity(0.3),
                    lineWidth: lineWidth
                )
            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear, value: progress)
        }
    }
}
