import AppIntents
import CloudStorage
import SonosKit

#if canImport(WidgetKit)
import WidgetKit
#endif

#if canImport(UIKit)
import UIKit
#endif

struct SetSleepTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Set Sleep Timer"
    static var description = IntentDescription(
        "Set a sleep timer on a Sonos speaker to automatically stop playback after a duration",
        categoryName: "Timer",
        searchKeywords: ["Sleep", "Timer", "Sleep Timer", "Auto Stop"]
    )
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static private var sonosService = SonosService.shared
    static private var liveActivityManager = LiveActivityManagerFactory.shared

    @Parameter(title: "Sonos Speaker")
    var room: SonosDeviceEntity?

    @Parameter(title: "Use Custom Duration", default: false)
    var useCustom: Bool

    @Parameter(title: "Duration", default: .oneHour)
    var duration: SleepTimerDuration

    @Parameter(
        title: "Minutes",
        description: "Custom duration in minutes",
        default: 60,
        inclusiveRange: (1, 720)
    )
    var customMinutes: Int

    static var parameterSummary: some ParameterSummary {
        When(\.$useCustom, .equalTo, true) {
            Summary("Set \(\.$customMinutes) minute sleep timer on \(\.$room)") {
                \.$useCustom
            }
        } otherwise: {
            Summary("Set \(\.$duration) sleep timer on \(\.$room)") {
                \.$useCustom
            }
        }
    }

    init(room: SonosDeviceEntity, duration: SleepTimerDuration) {
        self.room = room
        self.useCustom = false
        self.duration = duration
        self.customMinutes = 60
    }

    init(duration: SleepTimerDuration) {
        self.useCustom = false
        self.duration = duration
        self.customMinutes = 60
    }

    init() {
        self.useCustom = false
        self.duration = .oneHour
        self.customMinutes = 60
    }

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
        if room == nil, let requestedRoom = await requestRoomIfNeeded() {
            resolvedRoom = requestedRoom
        } else if let existingRoom = room {
            resolvedRoom = existingRoom
        } else {
            throw IntentError.message("No Sonos room selected")
        }

        guard let group = await Self.sonosService.getGroupCoordinatorWithRoom(roomID: resolvedRoom.id) else {
            throw IntentError.message("Failed to lookup Room")
        }

        let minutes = useCustom ? customMinutes : duration.minutes
        let swiftDuration = Duration.seconds(minutes * 60)
        await Self.sonosService.sleepTimer(group: group, duration: swiftDuration)
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
                dialog: "Which Sonos speaker would you like to set a sleep timer on?"
            )
            return chosen
        } catch {
            return nil
        }
    }
}

enum SleepTimerDuration: String, AppEnum, CaseIterable, Equatable {
    case fifteenMinutes = "15min"
    case thirtyMinutes = "30min"
    case fortyFiveMinutes = "45min"
    case oneHour = "1hour"
    case ninetyMinutes = "90min"
    case twoHours = "2hours"

    var minutes: Int {
        switch self {
        case .fifteenMinutes: return 15
        case .thirtyMinutes: return 30
        case .fortyFiveMinutes: return 45
        case .oneHour: return 60
        case .ninetyMinutes: return 90
        case .twoHours: return 120
        }
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Sleep Timer Duration")
    }

    static var caseDisplayRepresentations: [SleepTimerDuration: DisplayRepresentation] {
        [
            .fifteenMinutes: DisplayRepresentation(title: "15 Minutes"),
            .thirtyMinutes: DisplayRepresentation(title: "30 Minutes"),
            .fortyFiveMinutes: DisplayRepresentation(title: "45 Minutes"),
            .oneHour: DisplayRepresentation(title: "1 Hour"),
            .ninetyMinutes: DisplayRepresentation(title: "90 Minutes"),
            .twoHours: DisplayRepresentation(title: "2 Hours")
        ]
    }
}

#if !os(visionOS)
@available(iOS 18.0, *)
extension SetSleepTimerIntent: ControlConfigurationIntent { }
#endif
