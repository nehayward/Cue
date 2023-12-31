import SwiftUI
import SonosKit

struct DeviceCellView: View {
    @Environment(SonosService.self) private var sonosService: SonosService
    @Binding var group: GroupRoom

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: group.rooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill")
                    Text(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
                }
                Text(group.coordinatorRoom.track.name)
                    .lineLimit(0)
                    .redacted(reason: group.coordinatorRoom.track.name.isEmpty ? .placeholder : [])

                Text(group.coordinatorRoom.track.artist)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task {
                    if group.coordinatorRoom.isPlaying {
                        await sonosService.pause(ip: group.coordinatorRoom.ip)
                    } else {
                        await sonosService.play(ip: group.coordinatorRoom.ip)
                    }
                }
            } label: {
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
                .tint(group.coordinatorRoom.track.playbackPosition.isZero ? .clear : .accentColor)
                .gaugeStyle(.accessoryCircularCapacity)
                .scaleEffect(0.6)
                .frame(width: 24, height: 24)
            }
            .sensoryFeedback(trigger: group.coordinatorRoom.isPlaying) { old, new in
                new ? .start : .stop
            }
            .buttonStyle(.plain)
        }
        .tag(group.coordinatorID)
        .animation(.linear, value: group.coordinatorRoom.track.playbackPosition)
    }
}


#Preview {
    DeviceCellView(group: .constant(.theater))
        .environment(SonosService())
}
