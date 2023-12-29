import AppIntents
import CloudStorage
import SonosKit

struct TogglePlaybackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle Playback"
    static var description: IntentDescription = "This will toggle the playback of Sonos speaker"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static private var sonosService = SonosService()
    static private var liveActivityManager = LiveActivityManager(sonosService: Self.sonosService)

    @Parameter(title: "Sonos Speaker") var room: SonosDeviceEntity

    init(room: SonosDeviceEntity) {
        self.room = room
    }

    init() { }

    static var parameterSummary: some ParameterSummary {
        Summary("Toggle playback of \(\.$room)")
    }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in Clic")
        }

        guard let coordinatorGroup = await Self.sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else {
            throw IntentError.message("Failed to lookup Room")
        }
        
        await Self.sonosService.togglePlayback(ip: coordinatorGroup.ip)
        await Self.liveActivityManager.createActivity(id: room.id)
        await Self.liveActivityManager.refresh()
        return .result()
    }
}
