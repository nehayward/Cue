import AppIntents
import CloudStorage
import SonosKit

#if canImport(WidgetKit)
import WidgetKit
#endif

struct SetRelativeGroupVolumeIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Set Relative Volume"
    static var description = IntentDescription(
        "Change the volume of a Sonos speaker by a specific relative amount, increasing or decreasing the current level. (Defaults to group volume)",
        categoryName: "Volume"
    )

    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static private var sonosService = SonosService.shared
    static private var liveActivityManager = LiveActivityManagerFactory.shared

    @Parameter(title: "Sonos Speaker")
    var room: SonosDeviceEntity

    @Parameter(
        title: "Relative Volume",
        default: 2,
        controlStyle: .stepper,
        inclusiveRange: (-50, 50)
    )
    var value: Int
    
    @Parameter(
        title: "Adjust Room Volume Only",
        default: false
    )
    var roomOnly: Bool
    
    static var parameterSummary: some ParameterSummary {
        Summary("Adjust volume of \(\.$room) by \(\.$value)") {
            \.$roomOnly
        }
    }
    
    init(room: SonosDeviceEntity, volume: Int) {
        self.room = room
        self.value = volume
    }
    
    init() { }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in App")
        }
        
        guard !roomOnly else {
            await Self.sonosService.setRelativeVolume(ip: room.ip, volume: Int(value))
            try? await Task.sleep(for: .milliseconds(100))
            await Self.liveActivityManager.refresh()
    #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: "RemoteWidget")
    #endif
            return .result()
        }
        
        guard let coordinatorRoom = await Self.sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else {
            throw IntentError.message("Failed to lookup Room")
        }

        await Self.sonosService.setRelativeGroupVolume(ip: coordinatorRoom.ip, volume: Int(value))
        try? await Task.sleep(for: .milliseconds(100))
        await Self.liveActivityManager.refresh()
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "RemoteWidget")
#endif
        return .result()
    }
}
