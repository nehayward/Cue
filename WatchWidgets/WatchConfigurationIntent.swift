import WidgetKit
import AppIntents

struct WatchConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Configuration"
    static var description = IntentDescription("This is an example widget.")

    // An example configurable parameter.
    @Parameter(title: "Favorite Emoji", default: "😃")
    var favoriteEmoji: String
}


extension WatchConfigurationIntent {
    fileprivate static var smiley: WatchConfigurationIntent {
        let intent = WatchConfigurationIntent()
        intent.favoriteEmoji = "😀"
        return intent
    }

    fileprivate static var starEyes: WatchConfigurationIntent {
        let intent = WatchConfigurationIntent()
        intent.favoriteEmoji = "🤩"
        return intent
    }
}
