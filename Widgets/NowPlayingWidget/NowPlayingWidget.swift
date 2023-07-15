import AppIntents
import WidgetKit
import SonosKit
import SwiftUI

struct NowPlayingWidget: Widget {
    let kind: String = "NowPlayingWidget"

    var families: [WidgetFamily] {
        [.accessoryCircular, .accessoryRectangular, .systemSmall, .systemMedium]
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationNowPlayingAppIntent.self, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
        }
        .supportedFamilies(families)
        .contentMarginsDisabled()
    }
}

extension ConfigurationNowPlayingAppIntent {
    static var duaLipaInGarage: ConfigurationNowPlayingAppIntent {
        let intent = ConfigurationNowPlayingAppIntent()
        return intent
    }
}

