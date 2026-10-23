import Defaults
import SubscriptionKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Puts each answer `SubscriptionService` settles where code outside the app's
/// own state reads it: this device's App Group (`superUntil`), which the
/// Shortcuts actions check, and `SubscriptionService.resume(activeUntil:)`
/// starts from at the next launch. The only writer of it, and only ever with
/// an answer.
enum SuperPublisher {
    static func publish(_ subscription: Subscription) {
        GroupStorageKeys.defaults.superUntil = subscription.activeUntil ?? .distantPast
#if canImport(WidgetKit)
        if #available(visionOS 26.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
#endif
    }
}
