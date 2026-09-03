import AppIntents
import WidgetKit
import SwiftUI

struct NowPlayingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), configuration: WatchConfigurationIntent(), info: nil)
    }

    func snapshot(for configuration: WatchConfigurationIntent, in context: Context) async -> NowPlayingEntry {
        let entry = NowPlayingEntry(date: .now, configuration: configuration, info: nil)
        return entry
    }

    func timeline(for configuration: WatchConfigurationIntent, in context: Context) async -> Timeline<NowPlayingEntry> {
        let entry = NowPlayingEntry(date: .now, configuration: configuration, info: nil)
        return Timeline(entries: [entry], policy: .atEnd)
    }

    func recommendations() -> [AppIntentRecommendation<WatchConfigurationIntent>] {
        // Create an array with all the preconfigured widgets to show.
        [AppIntentRecommendation(intent: WatchConfigurationIntent(), description: "Cue")]
    }
}

struct NowPlayingEntry: TimelineEntry {
    var date: Date
    let configuration: WatchConfigurationIntent
    let info: Info?

    struct Info {
        let name: String
    }
}
