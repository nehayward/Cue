import AppIntents
import CloudStorage
import SonosKit
#if canImport(WidgetKit)
import WidgetKit
#endif

struct NextIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Next"
    static var description = IntentDescription(
        "Skips to the next song in the queue or radio station",
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
        Summary("Skip forward on \(\.$room)")
    }

    init() { }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.cue.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in App")
        }
        
        guard let coordinatorRoom = await Self.sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else {
            throw IntentError.message("Failed to lookup Room")
        }
        
        await Self.sonosService.next(ip: coordinatorRoom.ip)
        await Self.liveActivityManager.refresh()
        
        #if canImport(WidgetKit)
        if #available(visionOS 26.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
        return .result()
    }
}
