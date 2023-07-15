import AppIntents
import WidgetKit
import SwiftUI
import SonosKit

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: ConfigurationAppIntent(), volume: 0, track: nil)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: configuration, volume: 0, track: nil)
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        var entries: [SimpleEntry] = []

        if let ip = configuration.speakerIP?.ip {
            let sonosService = SonosService()

            let volume = await sonosService.getVolume(ip: ip)
            print(volume)

            let track = await sonosService.getTrack(ip: ip)
            print(track)


            var currentDate = Date()
            currentDate.addTimeInterval(60 * 30)
            let entry = SimpleEntry(date: currentDate, configuration: configuration, volume: volume, track: track)
            entries.append(entry)

            return Timeline(entries: entries, policy: .atEnd)
        }

        // Generate a timeline consisting of five entries an hour apart, starting from the current date.
        var currentDate = Date()
        currentDate.addTimeInterval(60 * 30)
        let entry = SimpleEntry(date: currentDate, configuration: configuration, volume: 0, track: nil)
        entries.append(entry)

        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let volume: Double
    let track: Track?
}

struct SonosWidget: Widget {
    private let kind: String = "SonosWidget"

    var families: [WidgetFamily] {
        [.accessoryCircular, .accessoryRectangular, .systemSmall, .systemMedium]
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
           SonosWidgetEntryView(entry: entry)
        }
        .supportedFamilies(families)
    }
}

#Preview(as: .systemMedium) {
    SonosWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(speakerIP: SonosSpeakerEntity(id: "", name: "Kitchen", ip: "", volume: 0)), volume: 0, track: Track(name: "Barbie", artist: "Dua Lipa", album: "Barbie", musicService: .apple, duration: 0, playbackPosition: 0))
}
