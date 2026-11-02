import Combine
import UIKit
import Observation
import RevenueCat
import Foundation
import Security

@Observable
public final class SubscriptionService {
    public static var shared = SubscriptionService()

    private static let apiKey = "appl_TSLqKDWEbyorETQwHuhHGoaYhCS"

    private var subscriptionTask: Task<Void, Never>?
    public var subscription: Subscription = .notActive
    /// Each answer, for the app to publish outside it (`SuperPublisher`). Only
    /// ever an answer: `subscription` is `.notActive` until one comes, and
    /// publishing that at launch locked the widgets and Shortcuts actions
    /// whenever Cue was suspended (overnight, in the background) before it came.
    public var subscriptionUpdated: ((Subscription) -> ())?
    /// TestFlight and Debug builds have Super without a purchase. TestFlight
    /// builds carry the App Store bundle ID, so this is how the answer's
    /// readers tell a tester's Super from a bought one.
    public private(set) var isGrantedByBuild = false
    private var protectedDataWait: AnyCancellable?
    private var evaluation = 0

    /// Empty until RevenueCat is configured, which waits for protected data
    /// (see `whenProtectedDataIsAvailable`). `Purchases.shared` is a fatal
    /// error before then, and an ID shown in Settings and a support email
    /// isn't worth taking the app down for.
    public var userID: String {
        guard Purchases.isConfigured else { return "" }
        return Purchases.shared.appUserID
    }

    /// Starts from this device's last answer (`Subscription.activeUntil`, as
    /// published) until RevenueCat or StoreKit gives a new one, so someone with
    /// Super doesn't see the free tier for a moment at launch. Called first in
    /// `AppBootstrapper.bootstrap`, from the app delegate, so background
    /// launches (CarPlay, downloads, a Shortcuts action) start from it too.
    /// Not an answer, so never announced.
    public func resume(activeUntil: Date?) {
        guard let activeUntil, activeUntil > .now, !subscription.isActive else { return }
        subscription = Subscription(isActive: true, expiration: activeUntil == .distantFuture ? nil : activeUntil)
    }

    /// Every answer goes to `subscriptionUpdated`, so set it first. `configured`
    /// runs once RevenueCat is, which can be later than this returns (see
    /// `whenProtectedDataIsAvailable`): don't touch `Purchases.shared` before.
    public func initialize(configured: @escaping () -> Void = {}) {
        Purchases.logLevel = .error
#if DEBUG && SUPER
        configure(environment: "DEBUG", appUserID: "DEBUG")
        configured()
        grantByBuild()
        return
#endif
        if UIApplication.shared.isRunningInTestFlightEnvironment() {
            configure(environment: "TESTFLIGHT")
            configured()
            grantByBuild()
            return
        }

        whenProtectedDataIsAvailable { [self] in
            configure(environment: "PRODUCTION")
            configured()
            followCustomerInfo()
        }
    }

    /// `appUserID` is a `String?` so a literal doesn't pick RevenueCat's
    /// deprecated `StaticString` overload.
    private func configure(environment: String, appUserID: String? = nil) {
        Purchases.configure(withAPIKey: Self.apiKey, appUserID: appUserID)
        Purchases.shared.attribution.setAttributes(["ENVIRONMENT": environment])
    }

    private func grantByBuild() {
        isGrantedByBuild = true
        subscription = .active
        subscriptionUpdated?(subscription)
    }

    /// RevenueCat reads its anonymous user ID from UserDefaults, which can't be
    /// read until the first unlock after a restart. Configured before then (a
    /// background launch after an overnight update), it starts a new user that
    /// owns nothing. `isProtectedDataAvailable` is false whenever the device
    /// is locked, so a background launch while locked waits too; that costs
    /// nothing, since nothing outside the app asks RevenueCat and the app
    /// starts from its last answer (`resume(activeUntil:)`).
    private func whenProtectedDataIsAvailable(_ body: @escaping () -> Void) {
#if targetEnvironment(macCatalyst)
        // A Mac app runs in a logged-in session, so its data is readable; and
        // waiting there for nothing would leave the paywall with RevenueCat
        // never configured.
        body()
#else
        guard !UIApplication.shared.isProtectedDataAvailable else {
            body()
            return
        }
        // The unlock is announced; coming forward also means it happened.
        let center = NotificationCenter.default
        protectedDataWait = center.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)
            .merge(with: center.publisher(for: UIApplication.didBecomeActiveNotification))
            .first { _ in UIApplication.shared.isProtectedDataAvailable }
            .sink { _ in body() }
#endif
    }

    /// RevenueCat's answer now (its cache, even a stale one, else the network;
    /// none offline), then each change it reports.
    private func followCustomerInfo() {
        subscriptionTask = Task { @MainActor in
            await apply(try? await Purchases.shared.customerInfo())
            for await customerInfo in Purchases.shared.customerInfoStream {
                await apply(customerInfo)
            }
        }
    }

    /// Asks again (coming forward, Settings, after a restore). Nothing to ask
    /// in TestFlight and Debug builds, or before RevenueCat is configured.
    @MainActor
    public func checkSubscription() async {
        guard !isGrantedByBuild, Purchases.isConfigured else { return }
        await apply(try? await Purchases.shared.customerInfo())
    }

    /// Settles Super from RevenueCat's answer (nil when it couldn't give one)
    /// and StoreKit's. Either saying yes is enough, and of two yeses the one
    /// that lasts longer counts. It's no only when RevenueCat answered no and
    /// StoreKit has nothing either; with no answer from RevenueCat and nothing
    /// in StoreKit, the last answer stands.
    @MainActor
    private func apply(_ customerInfo: CustomerInfo?) async {
        // RevenueCat's answers settle in the order they came, even when an
        // older one's StoreKit read finishes last. One without RevenueCat can
        // only add StoreKit's yes, which any of them would, so it isn't ordered.
        var thisEvaluation: Int?
        if customerInfo != nil {
            evaluation += 1
            thisEvaluation = evaluation
        }
        let fromRevenueCat = customerInfo.flatMap { Self.subscription(from: $0) }
        // A yes that never ends settles it without waiting on StoreKit. One
        // that ends (a cancelled plan) still asks: this install's RevenueCat
        // user may not know a Lifetime bought from another install.
        if let fromRevenueCat, fromRevenueCat.activeUntil == .distantFuture {
            subscription = fromRevenueCat
            subscriptionUpdated?(subscription)
            return
        }
        let fromStoreKit = await StoreKitEntitlements.subscription()
        if let thisEvaluation, thisEvaluation != evaluation { return }

        if let longer = Self.longer(fromRevenueCat, fromStoreKit) {
            subscription = longer
        } else if customerInfo != nil {
            subscription = .notActive
        } else {
            return
        }
        subscriptionUpdated?(subscription)
    }

    /// Of two answers, the yes that lasts longer; RevenueCat's on a tie.
    private static func longer(_ fromRevenueCat: Subscription?, _ fromStoreKit: Subscription?) -> Subscription? {
        guard let fromRevenueCat else { return fromStoreKit }
        guard let fromStoreKit else { return fromRevenueCat }
        let revenueCatUntil = fromRevenueCat.activeUntil ?? .distantPast
        let storeKitUntil = fromStoreKit.activeUntil ?? .distantPast
        return storeKitUntil > revenueCatUntil ? fromStoreKit : fromRevenueCat
    }

    /// RevenueCat's view: an active entitlement or subscription, or any one-off
    /// purchase (Lifetime).
    private static func subscription(from customerInfo: CustomerInfo) -> Subscription? {
        let info = customerInfo.entitlements.active.values.first?.toSubscriptionInfo
        // Lifetime first: it never ends, whatever subscription runs alongside.
        // Keep the entitlement only if it's Lifetime's (no end) too.
        if !customerInfo.nonSubscriptions.isEmpty {
            return Subscription(isActive: true, expiration: nil, info: info?.expirationDate == nil ? info : nil)
        }
        if !customerInfo.activeSubscriptions.isEmpty {
            return Subscription(isActive: true, expiration: customerInfo.latestExpirationDate, info: info)
        }
        if let info {
            return Subscription(isActive: true, expiration: info.expirationDate, info: info)
        }
        return nil
    }

}


extension UIApplication {
    /// A TestFlight build: its receipt is a sandbox one (on the Mac, its
    /// signature says so). Never in the simulator.
    func isRunningInTestFlightEnvironment() -> Bool {
#if targetEnvironment(simulator)
        return false
#elseif targetEnvironment(macCatalyst) || os(macOS)
        return Bundle.main.isTestFlight
#else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
#endif
    }
}

#if targetEnvironment(macCatalyst) || os(macOS)
extension Bundle {

    /// Returns whether the bundle was signed for TestFlight beta distribution by checking
    /// the existence of a specific extension (marker OID) on the code signing certificate.
    ///
    /// This routine is inspired by the source code from ProcInfo, the underlying library
    /// of the WhatsYourSign code signature checking tool developed by Objective-See. Initially,
    /// it checked the common name but was changed to an extension check to make it more
    /// future-proof.
    ///
    /// For more information, see the following references:
    /// - https://github.com/objective-see/ProcInfo/blob/master/procInfo/Signing.m#L184-L247
    /// - https://gist.github.com/lukaskubanek/cbfcab29c0c93e0e9e0a16ab09586996#gistcomment-3993808
    internal var isTestFlight: Bool {
        var status = noErr

        var code: SecStaticCode?
        status = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &code)

        guard status == noErr, let code = code else { return false }

        var requirement: SecRequirement?
        status = SecRequirementCreateWithString(
            "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.25.1]" as CFString,
            [], // default
            &requirement
        )

        guard status == noErr, let requirement = requirement else { return false }

        status = SecStaticCodeCheckValidity(
            code,
            [], // default
            requirement
        )

        return status == errSecSuccess
    }

}
#endif
