import AppIntents
import WidgetKit
import SonosKit
import SwiftUI

struct SceneWidget: Widget {
    let kind: String = "SceneWidget"

    var families: [WidgetFamily] {
        [.systemMedium]
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SceneWidgetConfigurationIntent.self, provider: SceneWidgetProvider()) { entry in
            SceneWidgetView(entry: entry)
        }
        .supportedFamilies(families)
    }
}
