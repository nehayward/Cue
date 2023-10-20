import AppIntents
import CloudStorage
import SonosKit

struct PreviousIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous media item."
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Sonos Device")
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
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in App")
        }

        let sonosService = SonosService()
        guard let coordinatorRoom = await sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else { return .result() }
        await sonosService.previous(ip: coordinatorRoom.ip)
        return .result()
    }
}
