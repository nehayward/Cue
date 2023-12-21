import AppIntents
import WidgetKit
import SwiftUI
import SonosKit

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RemoteWidgetEntry {
        RemoteWidgetEntry(date: Date(), configuration: RemoteWidgetConfigurationIntent(), volume: 0, track: nil)
    }

    func snapshot(for configuration: RemoteWidgetConfigurationIntent, in context: Context) async -> RemoteWidgetEntry {
        RemoteWidgetEntry(date: Date(), configuration: configuration, volume: 0, track: nil)
    }
    
    func timeline(for configuration: RemoteWidgetConfigurationIntent, in context: Context) async -> Timeline<RemoteWidgetEntry> {
        if let room = configuration.room {
            if let coordinatorRoom = await SonosService.shared.getGroupCoordinatorWithRoom(roomID: room.id), let volume = try? await SonosService.shared.getGroupVolume(ip: coordinatorRoom.ip) {
                let track = await SonosService.shared.getTrack(ip: coordinatorRoom.ip)
                let entry = RemoteWidgetEntry(date: .now, configuration: configuration, volume: volume, track: track)
                return Timeline(entries: [entry], policy: .atEnd)
            }
        }

        let entry = RemoteWidgetEntry(date: .now, configuration: configuration, volume: 0, track: nil)
        return Timeline(entries: [entry], policy: .atEnd)
    }
}

struct RemoteWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: RemoteWidgetConfigurationIntent
    let volume: Double
    let track: Track?
}

struct RemoteWidget: Widget {
    private let kind: String = "RemoteWidget"

    var families: [WidgetFamily] {
        [.systemSmall, .accessoryRectangular, .accessoryCircular]
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: RemoteWidgetConfigurationIntent.self, provider: Provider()) { entry in
           RemoteWidgetEntryView(entry: entry)
        }
        .supportedFamilies(families)
        .configurationDisplayName("Remote")
        .description("Select a Sonos device to control. Must be on Wi-Fi with Sonos system.") 
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry(date: .now, configuration: RemoteWidgetConfigurationIntent(room: SonosDeviceEntity(id: "", ip: "", name: "Kitchen", volume: 20)), volume: 20, track: Track(trackID: "", name: "Barbie", artist: "Dua Lipa", album: "Barbie", musicService: .apple, duration: 0, playbackPosition: 0))
}
