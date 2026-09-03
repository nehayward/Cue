import AppIntents
import CloudStorage
import SonosKit

#if canImport(WidgetKit)
    import WidgetKit
#endif

struct SetVolumeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Set Volume"
    static var description: IntentDescription = IntentDescription(
        "Adjust the volume of selected group from 0…100, (defaults to group volume)",
        categoryName: "Volume"
    )
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    
    static private var sonosService = SonosService.shared
    static private var liveActivityManager = LiveActivityManagerFactory.shared

    @Parameter(title: "Sonos Speaker")
    var room: SonosDeviceEntity

    @Parameter(
        title: "Volume",
        default: 20,
        controlStyle: .slider,
        inclusiveRange: (0, 100)
    )
    var volume: Double
    
    @Parameter(
        title: "Adjust Room Volume Only",
        default: false
    )
    var roomOnly: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Set volume of \(\.$room) to \(\.$volume)")
    }

    init(room: SonosDeviceEntity, volume: Double) {
        self.room = room
        self.volume = volume
    }

    init() {

    }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.cue.subscriptions") ?? false  else {
            throw IntentError.message("Subscribe to Super in App")
        }
        
        guard !roomOnly else {
            await Self.sonosService.setDeviceVolume(ip: room.ip, volume: Int(volume))
            try? await Task.sleep(for: .milliseconds(100))
            await Self.liveActivityManager.refresh()
    #if canImport(WidgetKit)
            if #available(visionOS 26.0, *) {
                WidgetCenter.shared.reloadTimelines(ofKind: "RemoteWidget")
            }
    #endif
            return .result()
        }
        
        guard let coordinatorRoom = await Self.sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else {
            throw IntentError.message("Failed to lookup Room")
        }
        
        await Self.sonosService.setGroupVolume(ip: coordinatorRoom.ip, volume: Int(volume))
        try? await Task.sleep(for: .milliseconds(100))
        await Self.liveActivityManager.refresh()
        #if canImport(WidgetKit)
        if #available(visionOS 26.0, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: "RemoteWidget")
        }
        #endif
        return .result()
    }
}
