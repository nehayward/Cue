import SwiftUI
import SonosKit

struct DeviceCellView: View {
    @Environment(SonosService.self) private var sonosService: SonosService
    @Binding var group: GroupRoom

    var body: some View {
        Section {
            HStack {
                VStack(alignment: .leading) {
                    if let settings = group.tvSettings {
                        Text(settings.audioInputFormat.description)
                    } else {
                        Text(group.coordinatorRoom.track.name)
                            .lineLimit(1, reservesSpace: true)
                            .redacted(reason: group.coordinatorRoom.track.name.isEmpty ? .placeholder : [])
                        Text(group.coordinatorRoom.track.artist)
                            .lineLimit(1, reservesSpace: true)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if group.tvSettings == nil {
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
                        .tint(group.coordinatorRoom.isPlaying ? .accentColor : Color.secondary)
                        .gaugeStyle(.accessoryCircularCapacity)
                        .scaleEffect(0.6)
                        .frame(width: 24, height: 24)
                    }
                    .sensoryFeedback(trigger: group.coordinatorRoom.isPlaying) { old, new in
                        new ? .start : .stop
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
           Text(group.nameWithCount)
        }
        .tag(group.coordinatorID)
        .animation(.linear, value: group.coordinatorRoom.track.playbackPosition)
    }
}


#Preview {
    DeviceCellView(group: .constant(.theater))
        .environment(SonosService())
}
