import WidgetKit
import AppIntents

struct SceneWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Scenes"
    static var description = IntentDescription("Run Scenes")
    
    @Parameter(title: "Scenes", default: [])
    var scenes: [SceneEntity]
    
    init() {

    }
}
