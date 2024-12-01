import AppIntents
import CloudStorage
import SonosKit

struct CreateLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Create Live Activity"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var isDiscoverable: Bool = false

    static private var liveActivityManager = LiveActivityManagerFactory.shared

    @Parameter(title: "Sonos Speaker") var room: SonosDeviceEntity?
    
    init(room: SonosDeviceEntity) {
        self.room = room
    }

    init() { }

    func perform() async throws -> some IntentResult {
        guard let id = room?.id else {
            throw IntentError.message("Please select room")
        }
        
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in Clic")
        }

        await Self.liveActivityManager.createActivity(id: id)
        await Self.liveActivityManager.refresh()
        return .result()
    }
}

#if !os(visionOS)
@available(iOS 18.0, *)
extension CreateLiveActivityIntent: ControlConfigurationIntent { }
#endif
