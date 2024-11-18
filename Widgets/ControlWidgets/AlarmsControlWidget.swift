import AppIntents
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 18.0, *)
struct AlarmsControlWidget: ControlWidget {
    static let kind: String = "com.clic.alarmControlWidget"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            intent: LaunchAlarmsIntent.self
        ) { configuration in
            ControlWidgetButton(action: configuration) {
                Image(systemName: "alarm")
                Text("Clic Alarms")
            }
        }
        .displayName("Alarms")
        .description("Must be on Wi-Fi with Sonos system. Tap to launch to alarm settings")
    }
}
