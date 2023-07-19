import AppIntents
import SonosKit

struct PlayPauseIntent: AppIntent {

    static var title: LocalizedStringResource = "Play/Pause Sonos Room"

    @Parameter(title: "Sonos Room")
    var room: SonosDeviceEntity

    init(room: SonosDeviceEntity) {
        self.room = room
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Play or pause \(\.$room)")
    }

    init() {

    }

    func perform() async throws -> some IntentResult {
        let sonosService = SonosService()
        guard let coordinatorRoom = await sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else { return .result() }
        await sonosService.playPauseDevice(ip: coordinatorRoom.ip)
        return .result()
    }
}
