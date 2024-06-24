import SwiftUI
import SonosKit

struct MiniPlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(SelectedGroupService.self) private var selectedGroupService

    @State var router = Router()
    @State var title = ""

    var body: some View {
        Group {
            if let groupID = selectedGroupService.group?.coordinatorID, let groupIndex = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }) {
                let group = sonosService.sorted[groupIndex]
                Button {
                    router.presentedSheet = .selectGroup(selectedGroupService: selectedGroupService)
                } label: {
                    HStack {
                        ContentArtworkView(content: group.coordinatorRoom.track.toPlayable)
                            .frame(width: 40, height: 40)
                            .animation(.bouncy, value: group.coordinatorRoom.track.trackID)
                            .id(group.coordinatorRoom.track.id)
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

                        Spacer()
                        if group.coordinatorRoom.track != .empty {
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

                            Button {
                                Task {
                                    HapticManager.shared.fireHaptic(.buttonPress)
                                    if group.coordinatorRoom.isPlaying {
                                        group.coordinatorRoom.isPlaying = false
                                        await sonosService.pause(ip: group.coordinatorRoom.ip)
                                    } else {
                                        group.coordinatorRoom.isPlaying = true
                                        await sonosService.play(ip: group.coordinatorRoom.ip)
                                    }
                                }
                            } label: {
                                if group.coordinatorRoom.track.duration > 0 {
                                    Gauge(
                                        value: group.coordinatorRoom.track.playbackPosition,
                                        in: 0...group.coordinatorRoom.track.duration,
                                        label: {

                                        },
                                        currentValueLabel: {
                                            Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                                                .renderingMode(.template)
                                                .foregroundStyle(group.coordinatorRoom.isPlaying ? .accent : .accent.opacity(0.7))
                                                .contentTransition(.symbolEffect(.automatic))

                                        }
                                    )
                                    .tint(group.coordinatorRoom.isPlaying ? .accent : .accent.opacity(0.7))
                                    .gaugeStyle(.accessoryCircularCapacity)
                                    .animation(.smooth, value: group.coordinatorRoom.track.playbackPosition)
                                    .scaleEffect(0.5)
                                    .frame(width: 20, height: 40, alignment: .center)
                                } else {
                                    Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                                        .renderingMode(.template)
                                        .foregroundColor(.accent)
                                        .contentTransition(.symbolEffect(.automatic))
                                        .frame(width: 20, height: 40, alignment: .center)
                                }
                            }
                            .buttonStyle(.plain)
                            .buttonBorderShape(.circle)
                        }
                    }
                }
                .transition(.push(from: .bottom))
            } else {
                Button {
                    router.presentedSheet = .selectGroup(selectedGroupService: selectedGroupService)
                } label: {
                    Text("Select Group")
                }
                .buttonStyle(.bordered)
                .tint(.accent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .animation(.bouncy.delay(0.2), value: selectedGroupService.group)
        // MARK: Debug Only
//        .task {
//            try? await SonosService.shared.updateGroups()
//            SonosService.shared.monitor()
//            group = SonosService.shared.sorted[1]
//        }
    }
}

//#Preview {
//    Text("Search")
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
//        .overlay(alignment: .bottom) {
//            MiniPlayerView(group: .constant(.gym))
//                .environment(SonosService.shared)
//        }
//}


