import AppIntents
import WidgetKit
import SwiftUI
import SonosKit

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: ConfigurationAppIntent(), volume: 0)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: configuration, volume: 0)
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        var entries: [SimpleEntry] = []

        if let ip = configuration.speakerIP?.ip {
            let sonosService = SonosService()
//            await sonosService.getTrack(ip: ip)
            let volume = await sonosService.getVolume(ip: ip)
            print(volume)

            var currentDate = Date()
            currentDate.addTimeInterval(60 * 30)
            let entry = SimpleEntry(date: currentDate, configuration: configuration, volume: volume)
            entries.append(entry)

            return Timeline(entries: entries, policy: .atEnd)
        }

        // Generate a timeline consisting of five entries an hour apart, starting from the current date.
        var currentDate = Date()
        currentDate.addTimeInterval(60 * 30)
        let entry = SimpleEntry(date: currentDate, configuration: configuration, volume: 0)
        entries.append(entry)

        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let volume: Double
}

struct SonosWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var widgetFamily: WidgetFamily

    @ViewBuilder
    var body: some View {
        if let speakerIP = entry.configuration.speakerIP {
            switch widgetFamily {
            case .accessoryRectangular:
                SonosWidgetLockScreenEntryView(entry: entry)
            case .accessoryCircular:
                Button(intent: PlayIntent()) {
                    Image(systemName: "playpause.circle.fill")
                }
            default:
                ZStack {
                    VStack {
                        Label(speakerIP.name, systemImage: "hifispeaker.fill")
                        
                        HStack {
                            Button(intent: PlayIntent()) {
                                Image(systemName: "playpause.circle.fill")
                            }
                            
                            Button(intent: PlayIntent()) {
                                Image(systemName: "forward.circle.fill")
                            }
                        }
                        .font(.largeTitle)
                        HStack {
                            Button(intent: SetVolumeIntent(speaker: speakerIP, volume: -5)) {
                                Image(systemName: "minus.circle.fill")
                            }
                            Button(intent: SetVolumeIntent(speaker: speakerIP, volume: 5)) {
                                Image(systemName: "plus.circle.fill")
                            }
                        }
                        .font(.largeTitle)
                        ProgressView(value: Double(entry.volume), total: 100)
                    }
                    .buttonStyle(.borderless)
                }
                .fontDesign(.rounded)
                .containerBackground(.thickMaterial, for: .widget)
            }
        } else {
           Label("No Wifi", systemImage: "wifi.slash")
                .containerBackground(.thickMaterial, for: .widget)
        }
    }
}

struct SonosWidgetLockScreenEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        if let speakerIP = entry.configuration.speakerIP {
            ZStack {
                VStack(alignment: .leading) {
                    Label(speakerIP.name, systemImage: "hifispeaker.fill")
                    HStack {
                        Button(intent: SetVolumeIntent(speaker: speakerIP, volume: -5)) {
                            Image(systemName: "minus.circle.fill")
                        }

                        Button(intent: PlayIntent()) {
                            Image(systemName: "playpause.circle.fill")
                        }

                        Button(intent: SetVolumeIntent(speaker: speakerIP, volume: 5)) {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                    .font(.largeTitle)
                    ProgressView(value: Double(entry.volume), total: 100)
                }
                .buttonStyle(.borderless)
            }
            .fontDesign(.rounded)
            .containerBackground(.secondary, for: .widget)
        } else {
           Label("No Wifi", systemImage: "wifi.slash")
                .containerBackground(.secondary, for: .widget)
        }
    }
}

struct SonosWidget: Widget {
    let kind: String = "SonosWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
           SonosWidgetEntryView(entry: entry)
        }
        .supportedFamilies([.accessoryRectangular, .systemSmall, .systemMedium, .accessoryCircular])
    }
}

extension ConfigurationAppIntent {
    fileprivate static var smiley: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "Garage"
        intent.speakerIP = SonosSpeakerEntity(id: "", name: "Kitchen", ip: "192.34", volume: 0)
        return intent
    }

    fileprivate static var smiley2: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "Kitchen"
        intent.speakerIP = SonosSpeakerEntity(id: "", name: "Kitchen", ip: "192.34", volume: 0)
        return intent
    }
}

#Preview(as: .accessoryRectangular) {
    SonosWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley, volume: 20)
    SimpleEntry(date: .now, configuration: .smiley2, volume: 0)
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), volume: 100)
}
