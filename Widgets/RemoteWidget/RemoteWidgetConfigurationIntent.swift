import WidgetKit
import AppIntents

struct RemoteWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Remote"
    static var description = IntentDescription("Select a Sonos device to control.")

    @Parameter(title: "Sonos Room")
    var room: SonosDeviceEntity?
    
    @Parameter(title: "Launch to Speaker", description: "Launch the app instead of starting Live Activity (Only applies to lock screen widgets)")
    var launchSpeaker: Bool?

    init(room: SonosDeviceEntity, launchApp: Bool = false) {
        self.room = room
        self.launchSpeaker = false
    }

    init() {
        launchSpeaker = false
    }
}
