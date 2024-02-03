import AppIntents
import CloudStorage
import WidgetKit
import SwiftUI
import SonosKit

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RemoteWidgetEntry {
        let activeSubscription = CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false
        return RemoteWidgetEntry(date: Date(), configuration: RemoteWidgetConfigurationIntent(), volume: 0, track: nil, activeSubscription: activeSubscription)
    }

    func snapshot(for configuration: RemoteWidgetConfigurationIntent, in context: Context) async -> RemoteWidgetEntry {
        let activeSubscription = CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false
        return RemoteWidgetEntry(date: Date(), configuration: configuration, volume: 0, track: nil, activeSubscription: activeSubscription)
    }
    
    func timeline(for configuration: RemoteWidgetConfigurationIntent, in context: Context) async -> Timeline<RemoteWidgetEntry> {
        let activeSubscription = CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false

        if let room = configuration.room {
            if let coordinatorRoom = await SonosService.shared.getGroupCoordinatorWithRoom(roomID: room.id), let volume = try? await SonosService.shared.getGroupVolume(ip: coordinatorRoom.ip) {
                let track = await SonosService.shared.getTrack(ip: coordinatorRoom.ip)
                var entry = RemoteWidgetEntry(
                    date: .now,
                    configuration: configuration,
                    volume: volume,
                    track: track,
                    name: coordinatorRoom.nameWithCount,
                    activeSubscription: activeSubscription
                )

//                // MARK: Mock
//                if room.name == "Theater" {
//                    if let TVSettings = try? await SonosService.shared.getTVSettings(ip: coordinatorRoom.ip) {
//                        entry.TVSettings = TVSettings
//                    }
//                    return Timeline(entries: [entry], policy: .atEnd)
//                }

                if track?.TVMode ?? false {
                    if let TVSettings = try? await SonosService.shared.getTVSettings(ip: coordinatorRoom.ip) {
                        entry.TVSettings = TVSettings
                    }
                }
                return Timeline(entries: [entry], policy: .atEnd)
            }
        }

        let entry = RemoteWidgetEntry(date: .now, configuration: configuration, volume: 0, track: nil, activeSubscription: activeSubscription)
        return Timeline(entries: [entry], policy: .atEnd)
    }
}

struct RemoteWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: RemoteWidgetConfigurationIntent
    let volume: Double
    let track: Track?
    var name: String? = nil
    var TVSettings: TVSettings? = nil
    var activeSubscription = false
}

struct RemoteWidget: Widget {
    private let kind: String = "RemoteWidget"
    @Environment(\.widgetFamily) var widgetFamily: WidgetFamily

    var families: [WidgetFamily] {
        [.accessoryRectangular, .accessoryCircular, .systemSmall]
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: RemoteWidgetConfigurationIntent.self, provider: Provider()) { entry in
           RemoteWidgetEntryView(entry: entry)
                .disabled(!entry.activeSubscription)
                .overlay {
                    if !entry.activeSubscription {
                        Circle()
                            .frame(maxWidth: 64, maxHeight: 64)
                            .foregroundStyle(.thinMaterial)
                            .overlay {
                                Image(systemName: "lock.fill")
                                    .font(widgetFamily == .accessoryRectangular ? .body : .title)
                            }
                            .widgetURL(URL(string: "clic://subscribe"))
                    }
                }
        }
        .supportedFamilies(families)
        .configurationDisplayName("Remote")
        .description("Select a Sonos device to control. Must be on Wi-Fi with Sonos system. Tap to start Live Activity.") 
        .contentMarginsDisabled()
    }
}

#Preview("Small", as: .systemSmall) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry(
        date: .now,
        configuration: RemoteWidgetConfigurationIntent(
            room: SonosDeviceEntity(
                id: "",
                ip: "",
                name: "Kitchen",
                volume: 20
            )
        ),
        volume: 20,
        track: Track(
            trackID: "",
            name: "Barbie",
            artist: "Dua Lipa",
            album: "Barbie",
            musicService: .apple,
            duration: 0,
            playbackPosition: 0,
            TVMode: false
        )
    )
}

#Preview("Circle", as: .accessoryCircular) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry(
        date: .now,
        configuration: RemoteWidgetConfigurationIntent(
            room: SonosDeviceEntity(
                id: "",
                ip: "",
                name: "Garage",
                volume: 20
            )
        ),
        volume: 20,
        track: .empty
    )
}

#Preview("Rectangle", as: .accessoryRectangular) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry(
        date: .now,
        configuration: RemoteWidgetConfigurationIntent(
            room: SonosDeviceEntity(
                id: "",
                ip: "",
                name: "Garage",
                volume: 20
            )
        ),
        volume: 20,
        track: .empty
    )
}

#Preview("Unlocked Rectangle", as: .accessoryRectangular) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry(
        date: .now,
        configuration: RemoteWidgetConfigurationIntent(
            room: SonosDeviceEntity(
                id: "",
                ip: "",
                name: "Garage",
                volume: 20
            )
        ),
        volume: 20,
        track: .empty,
        activeSubscription: true
    )
}
