import WidgetKit
import AppIntents

struct WatchConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Configuration"
    static var description = IntentDescription("Quickly launch Cue")
}
