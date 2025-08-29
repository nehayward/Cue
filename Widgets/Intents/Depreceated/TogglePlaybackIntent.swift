import AppIntents
import CloudStorage
import SonosKit
#if canImport(WidgetKit)
import WidgetKit
#endif

struct TogglePlaybackIntent: DeprecatedAppIntent {
    static var deprecation: IntentDeprecation<PlaybackIntent> = IntentDeprecation(message: "Please use the `PlaybackIntent` instead", replacedBy: PlaybackIntent.self)
    static var title: LocalizedStringResource = "Playback"
    static var description: IntentDescription = "Control playback of Sonos speaker"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static private var sonosService = SonosService.shared
    static private var liveActivityManager = LiveActivityManagerFactory.shared

    @Parameter(title: "Sonos Speaker") var room: SonosDeviceEntity

    init(room: SonosDeviceEntity) {
        self.room = room
    }

    init() { }

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
        #if canImport(WidgetKit)
        if #available(visionOS 26.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
        return .result()
    }
}
