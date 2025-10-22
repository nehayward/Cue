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
    @Parameter(title: "Always Ask", default: false) var requestRoom: Bool
    
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
        self.requestRoom = false
        self.room = room
        self.playback = playback
    }
    
    init(playback: PlaybackOption = .toggle) {
        self.requestRoom = false
        self.playback = playback
    }

    init(requestRoom: Bool) {
        self.requestRoom = requestRoom
    }
    
    init() { }
    
    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in Clic")
        }
        
        let resolvedRoom: SonosDeviceEntity
        if requestRoom, let requestedRoom = await requestRoomIfNeeded() {
            resolvedRoom = requestedRoom
        } else if let existingRoom = room {
            resolvedRoom = existingRoom
        } else {
            throw IntentError.message("No Sonos room selected")
        }

        guard let coordinatorRoom = await SonosService.shared.getGroupCoordinatorWithRoom(roomID: resolvedRoom.id) else {
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
        if #available(visionOS 26.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif

        return .result()
    }

    /// Requests the user to pick a Sonos room interactively if `room` is nil.
    private func requestRoomIfNeeded() async -> SonosDeviceEntity? {
        try? await SonosService.shared.updateGroups()
        let rooms = SonosService.shared.rooms
        guard !rooms.isEmpty else { return nil }

        do {
            let chosen = try await $room.requestDisambiguation(
                among: rooms.map {
                    SonosDeviceEntity(id: $0.id, ip: $0.ip, name: $0.name)
                },
                dialog: "Which Sonos speaker would you like to control?"
            )
            return chosen
        } catch {
            return nil
        }
    }
}

#if !os(visionOS)
@available(iOS 18.0, *)
extension PlaybackIntent: ControlConfigurationIntent { }
#endif
