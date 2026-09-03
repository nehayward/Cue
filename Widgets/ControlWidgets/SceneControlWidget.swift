import AppIntents
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 18.0, *)
struct SceneControlWidget: ControlWidget {
    static let kind: String = "com.cue.SceneControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            intent: RunSceneIntent.self
        ) { configuration in
            ControlWidgetButton(action: configuration) {
                Image(systemName: "bolt.fill")
                Text(configuration.scene?.name ?? "Please Configure")
            }
        }
        .displayName("Run Scene")
        .description("Run Scene in Cue")
        .promptsForUserConfiguration()
    }
}
