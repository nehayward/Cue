import AppIntents
import SonosKit

struct SetVolumeIntent: AppIntent {

    static var title: LocalizedStringResource = "Set Sonos Speaker Volume"

    @Parameter(title: "Sonos Speaker")
    var speaker: SonosSpeakerEntity

    @Parameter(title: "Desired Volume")
    var volume: Int

    init(speaker: SonosSpeakerEntity, volume: Int) {
        self.speaker = speaker
        self.volume = volume
    }
    
    init() {

    }

    func perform() async throws -> some IntentResult {
        let sonosService = SonosService()
        await sonosService.setRelativeVolume(ip: speaker.ip, volume: volume)
        return .result()
    }
}
