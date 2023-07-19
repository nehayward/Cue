import WidgetKit
import AppIntents

struct NowPlayingWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Now Playing"
    static var description = IntentDescription("Shows now playing")
    
    init() {

    }
}
