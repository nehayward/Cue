import AppIntents
import WidgetKit
import SonosKit
import SwiftUI

struct NowPlayingWidget: Widget {
    let kind: String = "NowPlayingWidget"

    var families: [WidgetFamily] {
        // MARK: TODO add back
//        [.accessoryCircular, .accessoryRectangular, .systemSmall, .systemMedium]
        [.systemMedium]
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: NowPlayingWidgetConfigurationIntent.self, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
        }
        .supportedFamilies(families)
    }
}
