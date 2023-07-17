import Foundation
import SwiftUI
import WidgetKit

struct WatchWidget: Widget {
    let kind: String = "WatchWidget"

    var families: [WidgetFamily] {
        [.accessoryCircular, .accessoryRectangular]
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: WatchConfigurationIntent.self,
                               provider: Provider()
        ) { entry in
            WatchWidgetsEntryView(entry: entry)
        }
        .supportedFamilies(families)
    }
}

#Preview(as: .accessoryCorner) {
    WatchWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: WatchConfigurationIntent())
}
