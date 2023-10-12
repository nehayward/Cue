import AppIntents
import SonosKit

struct NextIntent: AppIntent {
    static var sonosService = SonosService()
    static var liveActivityManager = LiveActivityManager(sonosService: Self.sonosService)

    static var title: LocalizedStringResource = "Next media item."

    @Parameter(title: "Sonos Speaker")
    var room: SonosDeviceEntity

    init(room: SonosDeviceEntity) {
        self.room = room
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Next track \(\.$room)")
    }

    init() {

    }

    func perform() async throws -> some IntentResult {
        guard let coordinatorRoom = await Self.sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else { return .result() }
        await Self.sonosService.next(ip: coordinatorRoom.ip)
        await Self.liveActivityManager.refresh()
        return .result()
    }
}
