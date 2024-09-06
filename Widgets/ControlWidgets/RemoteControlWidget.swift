import AppIntents
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 18.0, *)
struct RemoteControlWidget: ControlWidget {
    static let kind: String = "com.clic.RemoteControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            intent: CreateLiveActivityIntent.self
        ) { configuration in
            ControlWidgetButton(action: configuration) {
                Image(systemName: "hifispeaker.fill")
                Text(configuration.room?.name ?? "Please Configure")
            }
        }
        .displayName("Remote")
        .description("Select a Sonos device to control. Must be on Wi-Fi with Sonos system. Tap to start Live Activity.")
        .promptsForUserConfiguration()
    }
}
