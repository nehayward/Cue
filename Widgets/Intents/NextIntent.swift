import AppIntents
import CloudStorage
import SonosKit

struct NextIntent: AppIntent {
    static var title: LocalizedStringResource = "Next media item."
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static var sonosService = SonosService()
    static var liveActivityManager = LiveActivityManager(sonosService: Self.sonosService)

    @Parameter(title: "Sonos Device")
    var room: SonosDeviceEntity

    init(room: SonosDeviceEntity) {
        self.room = room
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Next track \(\.$room)")
    }

    init() {

    }

    func perform() async throws -> some ReturnsValue<Int> {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in App")
        }
        
        guard let coordinatorRoom = await Self.sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else { return .result(value: 0) }
        await Self.sonosService.next(ip: coordinatorRoom.ip)
        await Self.liveActivityManager.refresh()
        return .result(value: 1)
    }
}
