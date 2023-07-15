import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    init() {
        
    }
    
    static var title: LocalizedStringResource = "Configuration"
    static var description = IntentDescription("This is an example widget.")

    @Parameter(title: "Sonos Speaker")
    var speakerIP: SonosSpeakerEntity?

    init(speakerIP: SonosSpeakerEntity? = nil) {
        self.speakerIP = speakerIP
    }
}
