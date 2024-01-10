import AppIntents
import CloudStorage
import SonosKit

struct CreateLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Create Live Activity"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var isDiscoverable: Bool = false

    static private var liveActivityManager = LiveActivityManagerFactory.shared

    @Parameter(title: "Sonos Speaker") var room: SonosDeviceEntity

    init(room: SonosDeviceEntity) {
        self.room = room
    }

    init() { }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in Clic")
        }

        await Self.liveActivityManager.createActivity(id: room.id)
        await Self.liveActivityManager.refresh(type: .refresh)
        return .result()
    }
}
