import Mixpanel

final public class Analytics {
    public static var shared = Analytics()
    private var mixpanel: MixpanelInstance?
    private var userID: String?

    public func configure(token: String, userID: String) {
        self.userID = userID
        #if canImport(UIKit)
        let mixpanel = Mixpanel.initialize(token: token, trackAutomaticEvents: false, flushInterval: 15)
        mixpanel.identify(distinctId: userID)
        self.mixpanel = mixpanel
        #endif
    }

    public func track(_ event: AnalyticEvents, with metadata: [String: MixpanelType] = [:]) {
        mixpanel?.track(event: event.name, properties: metadata)
        #if DEBUG
        mixpanel?.flush()
        #endif
    }

    /// Overload for onboarding-funnel events. Forwards to the same Mixpanel
    /// track with the `onboarding_*` prefix already baked into `event.name`.
    public func track(_ event: OnboardingEvent, with metadata: [String: MixpanelType] = [:]) {
        mixpanel?.track(event: event.name, properties: metadata)
        #if DEBUG
        mixpanel?.flush()
        #endif
    }

    public func setSelection(metadata: [String: String]) {
        mixpanel?.registerSuperProperties(metadata)
        #if DEBUG
        mixpanel?.flush()
        #endif
    }
}
