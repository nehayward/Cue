import Foundation
import SwiftUI
import WidgetKit

struct WatchWidget: Widget {
    let kind: String = "WatchWidget"

    var families: [WidgetFamily] {
        [.accessoryCircular, .accessoryCorner]
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchConfigurationIntent.self,
                               provider: NowPlayingProvider()
        ) { entry in
            WatchWidgetsEntryView(entry: entry)
        }
        .supportedFamilies(families)
    }
}

#Preview(as: .accessoryCircular) {
    WatchWidget()
} timeline: {
    NowPlayingEntry(date: .now, configuration: WatchConfigurationIntent(), info: nil)
}
