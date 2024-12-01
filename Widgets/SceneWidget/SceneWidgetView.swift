import AppIntents
import WidgetKit
import SonosKit
import SwiftUI

struct SceneWidgetView: View {
    var entry: SceneEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SceneWidgetViewMedium(entry: entry)
        default:
           Text("Scene")
        }
    }
}

struct SceneWidgetViewMedium: View {
    var entry: SceneEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let scene = entry.configuration.scenes.first {
            Text(scene.name)
        }
    }
}

#Preview(as: .systemMedium) {
    SceneWidget()
} timeline: {
    SceneEntry(date: .now, configuration: .init(), info: nil)
}
