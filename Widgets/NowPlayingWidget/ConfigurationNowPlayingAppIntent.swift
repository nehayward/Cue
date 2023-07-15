import WidgetKit
import AppIntents

struct ConfigurationNowPlayingAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Now Playing"
    static var description = IntentDescription("Shows now playing")
}
