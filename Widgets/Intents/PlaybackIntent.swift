import AppIntents
import CloudStorage
import SonosKit
#if canImport(WidgetKit)
import WidgetKit
#endif

struct PlaybackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Set Playback"
    static var description = IntentDescription("Control playback of selected Sonos speaker or Group it's a part of", categoryName: "Playback", searchKeywords: ["Playback"])
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static private var liveActivityManager = LiveActivityManagerFactory.shared
    
    @Parameter(title: "Sonos Speaker") var room: SonosDeviceEntity?
    @Parameter(title: "Playback", default: .toggle) var playback: PlaybackOption
    
    static var parameterSummary: some ParameterSummary {
        Switch(\.$playback) {
            Case(.toggle) {
                Summary("\(\.$playback) playback \(\.$room)")
            }
            DefaultCase {
                Summary("\(\.$playback) \(\.$room)")
            }
        }
    }
    
    init(room: SonosDeviceEntity, playback: PlaybackOption = .toggle) {
        self.room = room
        self.playback = playback
    }

    init() { }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in Clic")
        }

        guard let room, let coordinatorRoom = await SonosService.shared.getGroupCoordinatorWithRoom(roomID: room.id) else {
            throw IntentError.message("Failed to lookup Room")
        }
        
        switch playback {
        case .play:
            await SonosService.shared.play(ip: coordinatorRoom.ip)
        case .pause:
            await SonosService.shared.pause(ip: coordinatorRoom.ip)
        case .toggle:
            await SonosService.shared.togglePlayback(ip: coordinatorRoom.ip)
        }
        
        try? await Task.sleep(for: .milliseconds(200))
        await Self.liveActivityManager.createActivity(id: coordinatorRoom.id)
        await Self.liveActivityManager.refresh()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        return .result()
    }
}

#if !os(visionOS)
@available(iOS 18.0, *)
extension PlaybackIntent: ControlConfigurationIntent { }
#endif
