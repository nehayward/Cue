import AppIntents
import CloudStorage
import WidgetKit
import SwiftUI
import SonosKit
import Defaults
import Collections

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RemoteWidgetEntry {
        let activeSubscription = CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false
        return RemoteWidgetEntry(
            date: Date(),
            configuration: RemoteWidgetConfigurationIntent(),
            playableContent: nil,
            volume: 0,
            isMuted: false,
            track: nil,
            activeSubscription: activeSubscription
        )
    }

    func snapshot(for configuration: RemoteWidgetConfigurationIntent, in context: Context) async -> RemoteWidgetEntry {
        let activeSubscription = CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false
        return RemoteWidgetEntry(
            date: Date(),
            configuration: configuration,
            playableContent: nil,
            volume: 0,
            isMuted: false,
            track: nil,
            activeSubscription: activeSubscription
        )
    }
    
    func timeline(for configuration: RemoteWidgetConfigurationIntent, in context: Context) async -> Timeline<RemoteWidgetEntry> {
        let activeSubscription = CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false

        if let room = configuration.room {
            if let group = await SonosService.shared.getGroupCoordinatorWithRoom(roomID: room.id),
                let volume = try? await SonosService.shared.getGroupVolume(ip: group.ip) {

                let track = await SonosService.shared.getTrackDetails(ip: group.ip)
                let isMuted = await SonosService.shared.isMuted(for: group)
                let playbackService = await SonosService.shared.playbackService(ip: group.ip)
                if let artworkURL = track?.artworkURL {
                    await ArtworkManager.shared.downScale(coordinatorRoom: group.nameWithCount, url: artworkURL)
                }
                
                let playHistory: OrderedSet<PlayableContent> = CloudStorageSync.shared.codable(forKey: CloudKeys.playHistory) ?? []

                var entry = RemoteWidgetEntry(
                    date: .now,
                    configuration: configuration,
                    playableContent: track?.toPlayable,
                    volume: volume,
                    isMuted: isMuted ?? false,
                    track: track,
                    name: group.nameWithCount,
                    activeSubscription: activeSubscription,
                    playHistory: Array(playHistory.elements.prefix(6))
                )

//                // MARK: Mock
//                if room.name == "Theater" {
//                    if let TVSettings = try? await SonosService.shared.getTVSettings(ip: coordinatorRoom.ip) {
//                        entry.TVSettings = TVSettings
//                    }
//                    return Timeline(entries: [entry], policy: .atEnd)
//                }

                if playbackService == .tv {
                    if let TVSettings = try? await SonosService.shared.getTVSettings(ip: group.ip) {
                        entry.TVSettings = TVSettings
                    }
                }
                return Timeline(entries: [entry], policy: .atEnd)
            }
        }

        let entry = RemoteWidgetEntry(
            date: .now,
            configuration: configuration,
            playableContent: nil,
            volume: 0,
            isMuted: false,
            track: nil,
            activeSubscription: activeSubscription
        )
        return Timeline(entries: [entry], policy: .atEnd)
    }
}

struct RemoteWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: RemoteWidgetConfigurationIntent
    let playableContent: PlayableContent?
    let volume: Double
    let isMuted: Bool
    let track: Track?
    var name: String? = nil
    var TVSettings: TVSettings? = nil
    var activeSubscription = false
    var playHistory: [PlayableContent] = [
        .init(title: "Music for a Sushi Restaurant", subtitle: "Harry Style", thumbnail: nil, artwork: nil, content: MediaContent.init(service: .apple, id: "", type: .album, location: nil)),
        .init(title: "Dance the Night", subtitle: "By Dua Lipa", thumbnail: nil, artwork: nil, content: MediaContent.init(service: .plex, id: "", type: .album, location: nil)),
        .init(title: "I Had Some Help (Feat. Morgan Wallen)", subtitle: "Post Malone, Morgan Wallen", thumbnail: nil, artwork: nil, content: MediaContent.init(service: .spotify, id: "", type: .track, location: nil))
    ]

    static func previewBarbie(_ active: Bool = true, service: MusicService = .apple) -> RemoteWidgetEntry { RemoteWidgetEntry(
        date: .now,
        configuration: RemoteWidgetConfigurationIntent(
            room: SonosDeviceEntity(
                id: "",
                ip: "",
                name: "Kitchen + 1"
            )
        ),
        playableContent: .init(title: "Dance the Night (From The Barbie Album)", subtitle: "Dua Lipa", thumbnail: nil, artwork: nil, content: .init(service: service, id: "123", type: .track, location: nil)),
        volume: 20,
        isMuted: true,
        track: Track(
            trackID: "",
            name: "Barbie",
            artist: "Dua Lipa",
            album: "Barbie",
            musicService: service,
            duration: 0,
            playbackPosition: 0
        ),
        activeSubscription: active)
    }

    static func previewTheater(_ active: Bool = true, service: MusicService = .apple) -> RemoteWidgetEntry { RemoteWidgetEntry(
        date: .now,
        configuration: RemoteWidgetConfigurationIntent(
            room: SonosDeviceEntity(
                id: "",
                ip: "",
                name: "Theater"
            )
        ),
        playableContent: nil,
        volume: 20,
        isMuted: false,
        track: Track(
            trackID: "",
            name: "Barbie",
            artist: "Dua Lipa",
            album: "Barbie",
            musicService: service,
            duration: 0,
            playbackPosition: 0
        ),
        TVSettings: .init(nightMode: true, dialogLevel: false, audioInputFormat: .dolbyDigital),
        activeSubscription: active)
    }
}

struct RemoteWidget: Widget {
    private let kind: String = "RemoteWidget"
    @Environment(\.widgetFamily) var widgetFamily: WidgetFamily

    var families: [WidgetFamily] {
        [.accessoryRectangular, .accessoryCircular, .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
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
                                    .widgetAccentable()
                            }
                            .widgetURL(URL(string: "clic://subscribe"))
                    }
                }
        }
        .supportedFamilies(families)
        .configurationDisplayName("Remote")
        .description("Select a Sonos device to control. Must be on Wi-Fi with Sonos system. Tap to start Live Activity.")
        .promptsForUserConfigurationIfiOS18()
    }
}

#Preview("Small", as: .systemSmall) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry.previewBarbie()
}

#Preview("Circle", as: .accessoryCircular) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry.previewBarbie()
}

#Preview("Rectangle", as: .accessoryRectangular) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry.previewBarbie()
}

#Preview("Unlocked Rectangle", as: .accessoryRectangular) {
    RemoteWidget()
} timeline: {
    RemoteWidgetEntry.previewBarbie()
}
