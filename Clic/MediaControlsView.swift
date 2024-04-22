import SwiftUI
import SonosKit

struct MediaControlsView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router

    @Binding var group: GroupRoom

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Button {
                router.presentedSheet = .groupScreen(group: group)
            } label: {
                Image(systemName: group.rooms.count > 1 ? "hifispeaker.2.fill" :  "hifispeaker.fill")
                    .frame(width: 20)
                    .foregroundStyle(.tint, .thickMaterial)
            }
            .buttonStyle(.plain)

            if group.coordinatorRoom.track != .empty {
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
                                    .foregroundColor(.accentColor)
                                    .contentTransition(.symbolEffect(.automatic))
                            }
                        )
                        .tint(group.coordinatorRoom.isPlaying ? .accentColor : Color.secondary)
                        .gaugeStyle(.accessoryCircularCapacity)
                        .animation(.linear, value: group.coordinatorRoom.track.playbackPosition)
                        .scaleEffect(0.5)
                        .frame(width: 20, height: 40, alignment: .center)
                    } else {
                        Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                            .renderingMode(.template)
                            .foregroundColor(.accentColor)
                            .contentTransition(.symbolEffect(.automatic))
                            .frame(width: 20, height: 40, alignment: .center)
                    }
                }
                .buttonStyle(.plain)
                .buttonBorderShape(.circle)
            }
        }
    }
}

#Preview {
    MediaControlsView(group: .constant(.garage))
        .environment(SonosService())
        .environment(Router())
}
