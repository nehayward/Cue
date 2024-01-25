import AppIntents
import CloudStorage
import SonosKit

struct NightModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Night Mode"
    static var description: IntentDescription = "Toggle night mode for TV"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static var sonosService = SonosService()
    static var liveActivityManager = LiveActivityManagerFactory.shared

    @Parameter(title: "Sonos Speaker") var room: SonosDeviceEntity
    @Parameter(title: "Night Mode") var nightMode: Bool

    init(room: SonosDeviceEntity, nightMode: Bool) {
        self.room = room
        self.nightMode = nightMode
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Toggle night mode for \(\.$room)")
    }

    init() { }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in App")
        }

        guard let coordinatorRoom = await Self.sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else {
            throw IntentError.message("Failed to lookup Room")
        }

        do {
            try await Self.sonosService.setNightMode(coordinatorRoom.ip, enabled: nightMode)
        } catch {
            throw IntentError.message("Night Mode not supported")
        }

        try? await Task.sleep(for: .milliseconds(250))
        await Self.liveActivityManager.refresh(type: .refresh)
        return .result()
    }
}
