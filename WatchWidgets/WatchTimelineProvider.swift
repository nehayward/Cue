import WidgetKit
import SwiftUI

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: WatchConfigurationIntent())
    }

    func snapshot(for configuration: WatchConfigurationIntent, in context: Context) async -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: configuration)
    }
    
    func timeline(for configuration: WatchConfigurationIntent, in context: Context) async -> Timeline<SimpleEntry> {
        var entries: [SimpleEntry] = []

        // Generate a timeline consisting of five entries an hour apart, starting from the current date.
        let currentDate = Date()
        for hourOffset in 0 ..< 5 {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
            var entry = SimpleEntry(date: entryDate, configuration: configuration)
            entries.append(entry)
        }

        entries[0].relevance = TimelineEntryRelevance(score: 10, duration: 60 * 60)

        return Timeline(entries: [], policy: .atEnd)
    }

    func recommendations() -> [AppIntentRecommendation<WatchConfigurationIntent>] {
        // Create an array with all the preconfigured widgets to show.
        [AppIntentRecommendation(intent: WatchConfigurationIntent(), description: "Example Widget")]
    }


}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: WatchConfigurationIntent
    var relevance: TimelineEntryRelevance? = nil
}

