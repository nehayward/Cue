import AppIntents
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 18.0, *)
struct LaunchAppControlWidget: ControlWidget {
    static let kind: String = "com.clic.launchControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            intent: LaunchSpeakerIntent.self
        ) { configuration in
            ControlWidgetButton(action: configuration) {
                Image("clic.icon.big")
                Text(configuration.room?.name ?? "Select Room")
            }
        }
        .displayName("Launcher")
        .description("Select a Sonos device to control. Must be on Wi-Fi with Sonos system. Tap to launch to selected room")
        .promptsForUserConfiguration()
    }
}
