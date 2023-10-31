import AppIntents
import CloudStorage
import SonosKit

struct NextIntent: AppIntent {
    static var title: LocalizedStringResource = "Next"
    static var description: IntentDescription = "Go to the next song in queue if available."
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static var sonosService = SonosService()
    static var liveActivityManager = LiveActivityManager(sonosService: Self.sonosService)

    @Parameter(title: "Sonos Speaker") var room: SonosDeviceEntity

    init(room: SonosDeviceEntity) {
        self.room = room
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Next item in queue on \(\.$room)")
    }

    init() { }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in App")
        }
        
        guard let coordinatorRoom = await Self.sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else {
            throw IntentError.message("Failed to lookup Room")
        }
        await Self.sonosService.next(ip: coordinatorRoom.ip)
        try? await Task.sleep(for: .milliseconds(300))
        await Self.liveActivityManager.refresh(updateType: .next)
        return .result()
    }
}
