import SwiftUI
import SonosKit
import WidgetKit

struct RemoteWidgetRectangularView: View {
    var entry: Provider.Entry

    var body: some View {
        if let room = entry.configuration.room {
            Button(intent: CreateLiveActivityIntent(room: room)) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.name ?? room.name)
                        .font(.caption)
                    if let track = entry.track {
                        Text(track.name)
                        Text(track.artist)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        ProgressView(value: Double(entry.volume), total: 100)
                            .tint(.accentColor)
                        Text("\(entry.volume, specifier: "%0.f")%")
                            .foregroundStyle(.primary)
                            .font(.caption)
                            .contentTransition(.numericText())
                    }
                }
                .fontDesign(.rounded)
                .bold()
            }
            .buttonStyle(.plain)
        } else {
            Label("No Wifi", systemImage: "wifi.slash")
                .containerBackground(.secondary, for: .widget)
        }

    }
}

#Preview("Active Subscription", as: .accessoryRectangular) {
    RemoteWidget(activeSubscription: true)
} timeline: {
    RemoteWidgetEntry(date: .now, configuration: RemoteWidgetConfigurationIntent(room: SonosDeviceEntity(id: "", ip: "", name: "Garage", volume: 20)), volume: 20, track: Track(trackID: "", name: "Barbie", artist: "Dua Lipa", album: "Barbie", musicService: .apple, duration: 0, playbackPosition: 0))
}

#Preview("No Subscription", as: .accessoryRectangular) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry(date: .now, configuration: RemoteWidgetConfigurationIntent(room: SonosDeviceEntity(id: "", ip: "", name: "Garage", volume: 20)), volume: 20, track: Track(trackID: "", name: "Barbie", artist: "Dua Lipa", album: "Barbie", musicService: .apple, duration: 0, playbackPosition: 0))
}
