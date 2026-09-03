import AppIntents
import CloudStorage

struct EndAllLiveActivitiesIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End All Live Activities"
    static var description = IntentDescription(
        "End all active Live Activities.",
        categoryName: "Live Activity"
    )
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static private var liveActivityManager = LiveActivityManagerFactory.shared

    static var parameterSummary: some ParameterSummary {
        Summary("End All Live Activities")
    }

    init() {}

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.cue.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in Cue")
        }

        await Self.liveActivityManager.endAll()
        return .result()
    }
}

#if !os(visionOS)
    @available(iOS 18.0, *)
    extension EndAllLiveActivitiesIntent: ControlConfigurationIntent {}
#endif


