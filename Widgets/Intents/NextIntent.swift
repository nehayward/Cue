import AppIntents
import SonosKit

struct NextIntent: AppIntent {
    static var title: LocalizedStringResource = "Nest media item."

    @Parameter(title: "Sonos Speaker")
    var speaker: SonosSpeakerEntity

    init(speaker: SonosSpeakerEntity) {
        self.speaker = speaker
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Nest track \(\.$speaker)")
    }

    init() {

    }

    func perform() async throws -> some IntentResult {
        let sonosService = SonosService()
        await sonosService.next(ip: speaker.ip)
        return .result()
    }
}
