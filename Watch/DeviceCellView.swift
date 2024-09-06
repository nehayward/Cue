import Nuke
import NukeUI
import SwiftUI
import SonosKit
import MusicSearchKit

struct DeviceCellView: View {
    @Environment(SonosService.self) private var sonosService: SonosService
    @Binding var group: GroupRoom

    var body: some View {
        Section {
            if group.coordinatorRoom.state == .active {
                HStack {
                    VStack(alignment: .leading) {
                        if let settings = group.tvSettings {
                            Text(settings.audioInputFormat.description)
                        } else {
                            HStack {
                                ThumbnailView(content: group.coordinatorRoom.track.toPlayable)
                                    .frame(width: 40, height: 40)
                                VStack(alignment: .leading) {
                                    Text(group.coordinatorRoom.track.song)
                                        .lineLimit(1, reservesSpace: true)
                                        .redacted(reason: group.coordinatorRoom.track.song.isEmpty ? .placeholder : [])
                                    Text(group.coordinatorRoom.track.artist)
                                        .lineLimit(1, reservesSpace: true)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Spacer()
                    if group.tvSettings == nil && group.coordinatorRoom.track != .empty {
                        Button {
                            Task {
                                if group.coordinatorRoom.isPlaying {
                                    WKInterfaceDevice.current().play(.click)
                                    group.coordinatorRoom.isPlaying = false
                                    await sonosService.pause(ip: group.coordinatorRoom.ip)
                                } else {
                                    WKInterfaceDevice.current().play(.click)
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
                                            .foregroundStyle(group.coordinatorRoom.isPlaying ? .accentColor : Color.accentColor.opacity(0.7))
                                            .contentTransition(.symbolEffect(.automatic))

                                    }
                                )
                                .tint(group.coordinatorRoom.isPlaying ? .accentColor : Color.accentColor.opacity(0.7))
                                .gaugeStyle(.accessoryCircularCapacity)
                                .animation(.smooth, value: group.coordinatorRoom.track.playbackPosition)
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
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Text(group.coordinatorRoom.state.reason)
                }
            }
        } header: {
            HStack {
                Text(group.nameWithCount)
                if let battery = group.coordinatorRoom.battery {
                    Spacer()
                    Text((battery.percentage / 100), format: .percent)
                        .foregroundStyle(.secondary)
                    if battery.chargingState == .charging {
                        Image(systemName: "battery.100percent.bolt")
                            .symbolRenderingMode(.hierarchical)
                            .font(.caption)
                            .foregroundStyle(battery.percentage > 90.0 ? Color.green.gradient : Color.orange.gradient)
                    }
                }
            }
            .fontDesign(.rounded)
            .headerProminence(.increased)
        }
        .tag(group.coordinatorID)
        .animation(.linear, value: group.coordinatorRoom.track.playbackPosition)
        .overlay(alignment: .center) {
            if sonosService.sorted.isEmpty {
                ProgressView()
            }
        }
    }
}


#Preview {
    DeviceCellView(group: .constant(.theater))
        .environment(SonosService())
}
