import AppIntents
import WidgetKit
import SonosKit
import SwiftUI


struct NowPlayingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), configuration: ConfigurationNowPlayingAppIntent(), data: nil, track: "")
    }

    func snapshot(for configuration: ConfigurationNowPlayingAppIntent, in context: Context) async -> NowPlayingEntry {
        if let ip = configuration.speakerIP?.ip {
            let sonosService = SonosService()
//            await sonosService.getTrack(ip: ip)
            let volume = await sonosService.getVolume(ip: ip)
            let track = await sonosService.getTrack(ip: ip)

            guard let track = await sonosService.getTrack(ip: ip) else {
                return NowPlayingEntry(date: Date(), configuration: configuration, data: nil, track: "")
            }

            guard let artworkURL = await sonosService.getArtwork(song: track.name, artist: track.artist, album: track.album) else {
                return NowPlayingEntry(date: Date(), configuration: configuration, data: nil, track: "")
            }

            let data = try? await URLSession.shared.data(from: artworkURL)
            var currentDate = Date()
            currentDate.addTimeInterval(60 * 30)

            let entry = NowPlayingEntry(date: currentDate, configuration: configuration, data: data?.0, track: track.name)
            return entry
        }

        return NowPlayingEntry(date: Date(), configuration: configuration, data: nil, track: "")
    }

    func timeline(for configuration: ConfigurationNowPlayingAppIntent, in context: Context) async -> Timeline<NowPlayingEntry> {
        var entries: [NowPlayingEntry] = []

        if let ip = configuration.speakerIP?.ip {
            let sonosService = SonosService()

            if let track = await sonosService.getTrack(ip: ip), let artworkURL = await sonosService.getArtwork(song: track.name, artist: track.artist, album: track.album) {
                let data = try? await URLSession.shared.data(from: artworkURL)
                var currentDate = Date()
                currentDate.addTimeInterval(60 * 30)

                let entry = NowPlayingEntry(date: currentDate, configuration: configuration, data: data?.0, track: track.name)
                entries.append(entry)
            }

            return Timeline(entries: entries, policy: .atEnd)
        }

        // Generate a timeline consisting of five entries an hour apart, starting from the current date.
        let currentDate = Date()
        let entry = NowPlayingEntry(date: currentDate, configuration: configuration, data: nil, track: "")
        entries.append(entry)

        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct NowPlayingEntry: TimelineEntry {
    var date: Date
    let configuration: ConfigurationNowPlayingAppIntent
    let data: Data?
    let track: String
}

struct SonosWidgetNowPlayingEntryView : View {
    var entry: NowPlayingProvider.Entry

    var body: some View {
        if let speakerIP = entry.configuration.speakerIP, let data = entry.data {
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: UIImage(data: data)!)
                    .resizable()
                Label(speakerIP.name, systemImage: "hifispeaker.fill")
                    .padding(4)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)

            }
            .overlay(alignment: .topLeading) {
                Text(entry.track)
                    .padding(4)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
            }
            .fontDesign(.rounded)
            .containerBackground(.thickMaterial, for: .widget)

        } else {
            VStack {
                Text("No Wifi")
                    .containerBackground(.fill.tertiary, for: .widget)
            }
        }
    }
}

struct SonosNowPlayingWidget: Widget {
    let kind: String = "SonosNowPlayingWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationNowPlayingAppIntent.self, provider: NowPlayingProvider()) { entry in
            SonosWidgetNowPlayingEntryView(entry: entry)
        }
        .supportedFamilies([.accessoryRectangular, .systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

extension ConfigurationNowPlayingAppIntent {
    fileprivate static var duaLipaInGarage: ConfigurationNowPlayingAppIntent {
        let intent = ConfigurationNowPlayingAppIntent()
        intent.speakerIP = SonosSpeakerEntity(id: "192.168.4.50", name: "Garage", ip: "192.168.4.50", volume: 0)
        return intent
    }
}

#Preview(as: .systemSmall) {
    SonosNowPlayingWidget()
} timeline: {
    NowPlayingEntry(date: .now, configuration: .duaLipaInGarage, data: UIImage(named: "duaLipa")?.jpegData(compressionQuality: 1), track: "Cry Your Heart Out")
}
