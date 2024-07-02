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
                Image(systemName: "hifispeaker.fill")
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 24)
            }
            .buttonStyle(.borderless)

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

#Preview {
    MediaControlsView(group: .constant(.garage))
        .environment(SonosService())
        .environment(Router())
}
