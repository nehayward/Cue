import AppIntents
import WidgetKit
import SonosKit

struct SetRelativeGroupVolumeIntent: AppIntent {
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
        let sonosService = SonosService()
        guard let coordinatorRoom = await sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else { return .result() }
        await sonosService.setRelativeGroupVolume(ip: coordinatorRoom.ip, volume: volume)
        WidgetCenter.shared.reloadTimelines(ofKind: "RemoteWidget")
        return .result()
    }
}
