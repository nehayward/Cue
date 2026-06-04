import AppIntents
import CloudStorage
import SonosKit

struct CreateLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start Live Activity"
    static var description = IntentDescription(
        "Start a Live Activity for a Sonos speaker.",
        categoryName: "Live Activity"
    )
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static private var liveActivityManager = LiveActivityManagerFactory.shared

    @Parameter(
        title: "Sonos Speaker",
        requestValueDialog: IntentDialog("Which speaker would you like to start a Live Activity for?")
    )
    var room: SonosDeviceEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Start Live Activity for \(\.$room)")
    }

    init(room: SonosDeviceEntity) {
        self.room = room
    }

    init() { }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in Clic")
        }

        // `room` is optional to satisfy ControlConfigurationIntent.
        // Prompt when running from Shortcuts without a pre-configured speaker.
        let resolvedRoom: SonosDeviceEntity
        if let room {
            resolvedRoom = room
        } else {
            resolvedRoom = try await $room.requestValue(
                IntentDialog("Which speaker would you like to start a Live Activity for?")
            )
        }

        guard let coordinatorRoom = await SonosService.shared.getGroupCoordinatorWithRoom(roomID: resolvedRoom.id) else {
            throw IntentError.message("Failed to lookup Room")
        }

        await Self.liveActivityManager.createActivity(id: coordinatorRoom.coordinatorID)
        await Self.liveActivityManager.refresh()
        return .result()
    }
}

#if !os(visionOS)
@available(iOS 18.0, *)
extension CreateLiveActivityIntent: ControlConfigurationIntent { }
#endif
