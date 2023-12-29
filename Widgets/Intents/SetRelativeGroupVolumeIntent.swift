import AppIntents
import CloudStorage
import WidgetKit
import SonosKit

struct SetRelativeGroupVolumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Relative Volume"
    static var description: IntentDescription = "Increase or decrease volume, example: +2 or -2"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static var sonosService = SonosService()
    static var liveActivityManager = LiveActivityManager(sonosService: Self.sonosService)
    
    @Parameter(title: "Sonos Speaker")
    var room: SonosDeviceEntity

    @Parameter(title: "Relative Volume")
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
        
        guard let coordinatorRoom = await Self.sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else {
            throw IntentError.message("Failed to lookup Room")
        }

        await Self.sonosService.setRelativeGroupVolume(ip: coordinatorRoom.ip, volume: volume)
        try? await Task.sleep(for: .milliseconds(250))
        await Self.liveActivityManager.refresh()
        WidgetCenter.shared.reloadTimelines(ofKind: "RemoteWidget")
        return .result()
    }
}
