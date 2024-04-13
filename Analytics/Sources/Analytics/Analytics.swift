import Mixpanel

final public class Analytics {
    public static var shared = Analytics()
    private var mixpanel: MixpanelInstance?
    private var userID: String?

    public func configure(token: String, userID: String) {
        self.userID = userID
        let mixpanel = Mixpanel.initialize(token: token, trackAutomaticEvents: false, flushInterval: 15)
        mixpanel.identify(distinctId: userID)
        self.mixpanel = mixpanel
    }

    public func track(_ event: AnalyticEvents, with metadata: [String: String] = [:]) {
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
