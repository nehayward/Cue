import SwiftUI
import SonosKit
import WidgetKit

struct RemoteWidgetAccessoryCircularView: View {
    var entry: Provider.Entry

    var body: some View {
        if let room = entry.configuration.room {
            Button(intent: CreateLiveActivityIntent(room: room)) {
                Gauge(value: entry.volume, in: 0...100) {
                    Text("\(entry.volume, specifier: "%0.f")%")
                        .contentTransition(.numericText())
                } currentValueLabel: {
                    Text(entry.name ?? room.name)
                        .font(.caption)
                        .fontDesign(.rounded)
                }
                .gaugeStyle(.accessoryCircular)
            }
            .buttonStyle(.plain)
            .containerBackground(.bar, for: .widget)
        } else {
            Label("No Wifi", systemImage: "wifi.slash")
                .containerBackground(.secondary, for: .widget)
        }

    }
}


#Preview(as: .accessoryCircular) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry(date: .now, configuration: RemoteWidgetConfigurationIntent(room: SonosDeviceEntity(id: "", ip: "", name: "Garage", volume: 20)), volume: 20, track: Track(trackID: "", name: "Barbie", artist: "Dua Lipa", album: "Barbie", musicService: .apple, duration: 0, playbackPosition: 0))
}
