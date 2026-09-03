import AppIntents
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 18.0, *)
struct StartLiveActivityControlWidget: ControlWidget {
    static let kind: String = "com.cue.StartLiveActivity"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            intent: CreateLiveActivityIntent.self
        ) { configuration in
            ControlWidgetButton(action: configuration) {
                Image(systemName: "plus.capsule.fill")
                Text(configuration.room?.name ?? "Choose Speaker")
            }
        }
        .displayName("Start Live Activity")
        .description("Start a Live Activity for a Sonos speaker.")
        .promptsForUserConfiguration()
    }
}
