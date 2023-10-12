import AppIntents
import SonosKit

struct PreviousIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous media item."

    @Parameter(title: "Sonos Speaker")
    var room: SonosDeviceEntity

    init(room: SonosDeviceEntity) {
        self.room = room
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Previous track \(\.$room)")
    }

    init() {

    }

    func perform() async throws -> some IntentResult {
        let sonosService = SonosService()
        guard let coordinatorRoom = await sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else { return .result() }
        await sonosService.previous(ip: coordinatorRoom.ip)
        return .result()
    }
}
