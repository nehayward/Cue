import AppIntents
import CloudStorage
import UIKit
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
    @Parameter(
        title: "Speaker Only",
        description: "Mute only this speaker instead of the entire group",
        default: false
    )
    var roomOnly: Bool
    
    static var parameterSummary: some ParameterSummary {
        Switch(\.$mute) {
            Case(.toggle) {
                Summary("\(\.$mute) mute on \(\.$room)") {
                    \.$roomOnly
                }
            }
            Case(.mute) {
                Summary("Mute \(\.$room)"){
                    \.$roomOnly
                }
            }
            Case(.unmute) {
                Summary("Unmute \(\.$room)"){
                    \.$roomOnly
                }
            }
            DefaultCase {
                Summary("\(\.$mute) \(\.$room)"){
                    \.$roomOnly
                }
            }
        }
    }
    
    init(room: SonosDeviceEntity, mute: MuteOption = .toggle, roomOnly: Bool = false) {
        self.room = room
        self.mute = mute
        self.roomOnly = roomOnly
    }

    init() { }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            guard
                let url = URL(string: "clic://subscribe"),
                let application = UIApplication.value(forKeyPath: #keyPath(UIApplication.shared)) as? UIApplication
            else {
                throw IntentError.message("Subscribe to Super in Clic")
            }
            
            await application.open(url)
            throw IntentError.message("Subscribe to Super in Clic")
        }
        
        guard let room, let group = await SonosService.shared.getGroupCoordinatorWithRoom(roomID: room.id) else {
            throw IntentError.message("Failed to lookup Room")
        }
        
        guard !roomOnly else {
            switch mute {
            case .mute:
                await SonosService.shared.setRoomMute(IP: room.ip, mute: true)
            case .unmute:
                await SonosService.shared.setRoomMute(IP: room.ip, mute: false)
            case .toggle:
                let mute = await SonosService.shared.isRoomMuted(for: room.ip) ?? false
                await SonosService.shared.setRoomMute(IP: room.ip, mute: !mute)
            }
            return .result()
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
