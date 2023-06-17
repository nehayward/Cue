import AppIntents
import SonosKit

struct PlayIntent: AppIntent {

    static var title: LocalizedStringResource = "Play Sonos"

    @Parameter(title: "Sonos Speaker")
    var speaker: SonosSpeakerEntity

    init(speaker: SonosSpeakerEntity) {
        self.speaker = speaker
    }

    init() {

    }

    func perform() async throws -> some IntentResult {
        let sonosService = SonosService()
        await sonosService.playDevice(ip: speaker.ip)
        return .result()
    }
}


struct SonosSpeakerEntity: AppEntity, Identifiable {
    var id: String
    var name: String
    var ip: String
    var volume: Int

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Speaker"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(stringLiteral: name)
    }

    static var defaultQuery = SpeakerQuery()
}
