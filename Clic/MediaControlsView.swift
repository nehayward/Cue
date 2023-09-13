import SwiftUI
import SonosKit

struct MediaControlsView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom

    @State var showGroupScreen: Bool = false

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Button(action: {
                Task {
                    if group.coordinatorRoom.isPlaying {
                        group.coordinatorRoom.isPlaying = false
                        await sonosService.pause(ip: group.coordinatorRoom.ip)
                    } else {
                        group.coordinatorRoom.isPlaying = true
                        await sonosService.play(ip: group.coordinatorRoom.ip)
                    }
                }
            }, label: {
                Gauge(
                    value: group.coordinatorRoom.track.playbackPosition,
                    in: 0...group.coordinatorRoom.track.duration,
                    label: {

                    },
                    currentValueLabel: {
                        Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                            .renderingMode(.template)
                            .foregroundColor(.accentColor)
                            .contentTransition(.symbolEffect(.automatic))
                    }
                )
                .tint(.accentColor)
                .gaugeStyle(.accessoryCircularCapacity)
                .animation(.linear, value: group.coordinatorRoom.track.playbackPosition)
                .scaleEffect(0.5)
                .frame(width: 20, height: 40, alignment: .center)

            })
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: group.coordinatorRoom.isPlaying)

            Button(action: {
                showGroupScreen = true
            }, label: {
                Image(systemName: group.rooms.count > 1 ? "hifispeaker.2.fill" :  "hifispeaker.fill")
                    .frame(width: 20)
                    .foregroundStyle(.tint, .thickMaterial)
            })
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showGroupScreen) {
            GroupScreen(group: group, viewModel: GroupScreenViewModel(group: group))
        }
    }
}

#Preview {
    MediaControlsView(group: .constant(.garage))
        .environment(SonosService())
}
