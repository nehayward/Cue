import AppIntents
import CloudStorage
import SonosKit

struct RefreshIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Refresh"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var isDiscoverable: Bool = false

    static private var sonosService = SonosService()
    static private var liveActivityManager = LiveActivityManager(sonosService: Self.sonosService)

    init() { }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in Clic")
        }

        await Self.liveActivityManager.refresh(updateType: .refresh)
        return .result()
    }
}
