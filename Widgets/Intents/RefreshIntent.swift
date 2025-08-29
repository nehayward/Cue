import AppIntents
import CloudStorage
import SonosKit
#if canImport(WidgetKit)
import WidgetKit
#endif
import SwiftUI

struct RefreshIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Refresh"
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var isDiscoverable: Bool = false

    static private var liveActivityManager = LiveActivityManagerFactory.shared

    init() { }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in Clic")
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
