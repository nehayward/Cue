import AppIntents
import CloudStorage
import WidgetKit
import SonosKit

struct SetRelativeGroupVolumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Sonos Device Volume"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static var sonosService = SonosService()
    static var liveActivityManager = LiveActivityManager(sonosService: Self.sonosService)
    
    @Parameter(title: "Sonos Device")
    var room: SonosDeviceEntity

    @Parameter(title: "Desired Volume")
    var volume: Int

    init(room: SonosDeviceEntity, volume: Int) {
        self.room = room
        self.volume = volume
    }
    
    init() {

    }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in App")
        }
        
        guard let coordinatorRoom = await Self.sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else { return .result() }
        await Self.sonosService.setRelativeGroupVolume(ip: coordinatorRoom.ip, volume: volume)
        await Self.liveActivityManager.refresh()
        WidgetCenter.shared.reloadTimelines(ofKind: "RemoteWidget")
        return .result()
    }
}
