import AppIntents
import SonosKit

struct PlayIntent: AppIntent {

    static var title: LocalizedStringResource = "Play Sonos"

    @Parameter(title: "Sonos Speaker")
    var speaker: SonosSpeakerEntity

    init(speaker: SonosSpeakerEntity) {
        self.speaker = speaker
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$speaker)")
    }


    init() {

    }

    func perform() async throws -> some IntentResult {
//        LiveActivityManager.shared.refresh()
        let sonosService = SonosService()
        await sonosService.playDevice(ip: speaker.ip)
        
        return .result()
    }
}
