import AppIntents
import CloudStorage
import SonosKit

struct PreviousIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous"
    static var description: IntentDescription = "Go to the previous song in queue if available."
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static var sonosService = SonosService()
    static private var liveActivityManager = LiveActivityManagerFactory.shared

    @Parameter(title: "Sonos Speaker") var room: SonosDeviceEntity

    init(room: SonosDeviceEntity) {
        self.room = room
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Previous item in queue on \(\.$room)")
    }

    init() { }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in App")
        }

        guard let coordinatorRoom = await Self.sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else {
            throw IntentError.message("Failed to lookup Room")
        }

        await Self.sonosService.previous(ip: coordinatorRoom.ip)
        try? await Task.sleep(for: .milliseconds(250))
        await Self.liveActivityManager.refresh(type: .refresh)
        return .result()
    }
}
