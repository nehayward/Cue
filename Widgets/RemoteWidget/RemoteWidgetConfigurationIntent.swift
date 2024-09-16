import WidgetKit
import AppIntents

struct RemoteWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Remote"
    static var description = IntentDescription("Select a Sonos device to control.")

    @Parameter(title: "Sonos Room")
    var room: SonosDeviceEntity?
    
    @Parameter(title: "Launch to Speaker", description: "Launch the app instead of starting Live Activity", default: false)
    var launchSpeaker: Bool
    
    @Parameter(title: "Background", description: "Plain background", default: false)
    var plainBackground: Bool
    
    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .oneOf, [.accessoryRectangular, .accessoryCircular]) {
            Summary {
                \.$room
                \.$launchSpeaker
            }
        } otherwise: {
            When(widgetFamily: .equalTo, .systemMedium) {
                Summary {
                    \.$room
                    \.$plainBackground
                }
            } otherwise: {
                Summary {
                    \.$room
                }
            }
        }
    }

    init(room: SonosDeviceEntity, launchApp: Bool = false, plainBackground: Bool = false) {
        self.room = room
        self.launchSpeaker = launchApp
        self.plainBackground = plainBackground
    }

    init() {
        launchSpeaker = false
        plainBackground = false
    }
}
