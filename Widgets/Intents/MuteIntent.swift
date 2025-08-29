import AppIntents
import CloudStorage
import SonosKit
#if canImport(WidgetKit)
import WidgetKit
#endif

struct MuteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Set Mute"
    static var description = IntentDescription("Control mute of selected Sonos speaker or Group it's a part of", categoryName: "Volume", searchKeywords: ["Mute", "Volume"])
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static private var liveActivityManager = LiveActivityManagerFactory.shared
    
    @Parameter(title: "Sonos Speaker") var room: SonosDeviceEntity?
    @Parameter(title: "Mute", default: .toggle) var mute: MuteOption
    
    static var parameterSummary: some ParameterSummary {
        Switch(\.$mute) {
            Case(.toggle) {
                Summary("\(\.$mute) mute \(\.$room)")
            }
            DefaultCase {
                Summary("\(\.$mute) \(\.$room)")
            }
        }
    }
    
    init(room: SonosDeviceEntity, mute: MuteOption = .toggle) {
        self.room = room
        self.mute = mute
    }

    init() { }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in Clic")
        }

        guard let room, let group = await SonosService.shared.getGroupCoordinatorWithRoom(roomID: room.id) else {
            throw IntentError.message("Failed to lookup Room")
        }
        
        switch mute {
        case .mute:
            await SonosService.shared.setGroupMute(group: group, mute: true)
        case .unmute:
            await SonosService.shared.setGroupMute(group: group, mute: false)
        case .toggle:
            let mute = await SonosService.shared.isMuted(for: group) ?? false
            await SonosService.shared.setGroupMute(group: group, mute: !mute)
        }
        await Self.liveActivityManager.refresh()
        #if canImport(WidgetKit)
        if #available(visionOS 26.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
        return .result()
    }
}

enum MuteOption: String, AppEnum, CaseIterable, Equatable {
    case mute = "mute"
    case unmute = "unmute" 
    case toggle = "toggle"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Mute Option")
    }
    
    static var caseDisplayRepresentations: [MuteOption: DisplayRepresentation] {
        [
            .mute: DisplayRepresentation(title: "Mute"),
            .unmute: DisplayRepresentation(title: "Unmute"),
            .toggle: DisplayRepresentation(title: "Toggle Mute")
        ]
    }
}

#if !os(visionOS)
@available(iOS 18.0, *)
extension MuteIntent: ControlConfigurationIntent { }
#endif
