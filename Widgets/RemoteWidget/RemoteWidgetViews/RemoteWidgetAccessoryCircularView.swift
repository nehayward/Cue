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
            .invalidatableContent()
            .disabled(entry.configuration.launchSpeaker ?? false)
            .widgetURL(URL(string: "clic://device?id=\(room.id)"))
        } else {
            Label("No Wifi", systemImage: "wifi.slash")
                .containerBackground(.secondary, for: .widget)
        }

    }
}


#Preview(as: .accessoryCircular) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry.previewBarbie()
}
