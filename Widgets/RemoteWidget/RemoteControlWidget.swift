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
    }
}

struct StartTimerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Start a timer"

    @Parameter(title: "Timer Name")
    var name: String

    @Parameter(title: "Timer is running")
    var value: Bool

    init() {}

    init(_ name: String) {
        self.name = name
    }

    func perform() async throws -> some IntentResult {
        // Start the timer…
        return .result()
    }
}
