import AppIntents
import Defaults
import SonosKit

struct PreviousIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Previous"
    static var description = IntentDescription(
        "Go to the previous song in queue if available.",
        categoryName: "Playback"
    )
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static private var sonosService = SonosService.shared
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
        guard GroupStorageKeys.defaults.hasSuper else {
            throw IntentError.superRequired
        }

        guard let coordinatorRoom = await Self.sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else {
            throw IntentError.message("Failed to lookup Room")
        }

        await Self.sonosService.previous(ip: coordinatorRoom.ip)
        try? await Task.sleep(for: .milliseconds(250))
        await Self.liveActivityManager.refresh()
        return .result()
    }
}
