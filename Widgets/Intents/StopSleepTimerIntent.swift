import AppIntents
import CloudStorage
import SonosKit

#if canImport(WidgetKit)
import WidgetKit
#endif

#if canImport(UIKit)
import UIKit
#endif

struct StopSleepTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Sleep Timer"
    static var description = IntentDescription(
        "Cancel an active sleep timer on a Sonos speaker",
        categoryName: "Timer",
        searchKeywords: ["Sleep", "Timer", "Cancel", "Stop"]
    )
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static private var sonosService = SonosService.shared
    static private var liveActivityManager = LiveActivityManagerFactory.shared

    @Parameter(title: "Sonos Speaker")
    var room: SonosDeviceEntity?

    @Parameter(title: "Always Ask", default: false)
    var requestRoom: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Stop sleep timer on \(\.$room)")
    }

    init(room: SonosDeviceEntity) {
        self.requestRoom = false
        self.room = room
    }

    init(requestRoom: Bool) {
        self.requestRoom = requestRoom
    }

    init() { }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            #if canImport(UIKit) && !os(watchOS)
            if let url = URL(string: "clic://subscribe"),
               let application = UIApplication.value(forKeyPath: #keyPath(UIApplication.shared)) as? UIApplication {
                await application.open(url)
            }
            #endif
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

        guard let group = await Self.sonosService.getGroupCoordinatorWithRoom(roomID: resolvedRoom.id) else {
            throw IntentError.message("Failed to lookup Room")
        }

        await Self.sonosService.stopSleepTimer(group: group)

        return .result()
    }

    private func requestRoomIfNeeded() async -> SonosDeviceEntity? {
        try? await Self.sonosService.updateGroups()
        let rooms = Self.sonosService.rooms
        guard !rooms.isEmpty else { return nil }

        do {
            let chosen = try await $room.requestDisambiguation(
                among: rooms.map {
                    SonosDeviceEntity(id: $0.id, ip: $0.ip, name: $0.name)
                },
                dialog: "Which Sonos speaker would you like to stop the sleep timer on?"
            )
            return chosen
        } catch {
            return nil
        }
    }
}

#if !os(visionOS)
@available(iOS 18.0, *)
extension StopSleepTimerIntent: ControlConfigurationIntent { }
#endif
