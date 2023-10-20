import AppIntents
import CloudStorage
import SonosKit

struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play/Pause"
    static var description: IntentDescription = "Play/Pause Sonos Device"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Sonos Device")
    var room: SonosDeviceEntity

    init(room: SonosDeviceEntity) {
        self.room = room
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Play or pause \(\.$room)")
    }

    init() {

    }

    func perform() async throws -> some ReturnsValue<Int> {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in Clic")
        }

        let sonosService = SonosService()
        guard let coordinatorRoom = await sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else { return .result(value: 1) }
        await sonosService.playPauseDevice(ip: coordinatorRoom.ip)
        return .result(value: 1)
    }
}
