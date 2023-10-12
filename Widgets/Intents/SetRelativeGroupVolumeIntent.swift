import AppIntents
import WidgetKit
import SonosKit

struct SetRelativeGroupVolumeIntent: AppIntent {
    static var sonosService = SonosService()
    static var liveActivityManager = LiveActivityManager(sonosService: Self.sonosService)

    static var title: LocalizedStringResource = "Set Sonos Device Volume"

    @Parameter(title: "Sonos Room")
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
        guard let coordinatorRoom = await Self.sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else { return .result() }
        await Self.sonosService.setRelativeGroupVolume(ip: coordinatorRoom.ip, volume: volume)
        await Self.liveActivityManager.refresh()
        WidgetCenter.shared.reloadTimelines(ofKind: "RemoteWidget")
        return .result()
    }
}
