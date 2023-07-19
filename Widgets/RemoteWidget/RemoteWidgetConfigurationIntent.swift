import WidgetKit
import AppIntents

struct RemoteWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Remote"
    static var description = IntentDescription("Select a Sonos device to control.")

    @Parameter(title: "Sonos Room")
    var room: SonosDeviceEntity?

    init(room: SonosDeviceEntity) {
        self.room = room
    }

    init() {

    }
}
