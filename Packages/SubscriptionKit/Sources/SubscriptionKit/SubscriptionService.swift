import CloudStorage
import CloudKit
import UIKit
import Observation
import RevenueCat
import Foundation
import Security

@Observable
public final class SubscriptionService {
    public static var shared = SubscriptionService()

    private var subscriptionTask: Task<Void, Error>?
    private let sync = CloudStorageSync.shared
    public var subscription: Subscription = .notActive
    public var subscriptionUpdated: ((Subscription) -> ())?
    private var keyID: String?

    public var userID: String {
        return Purchases.shared.appUserID
    }

    public func initialize(key: String, mock: Bool = false) {
        self.keyID = key
        guard let keyID else { return }

#if DEBUG && SUPER
        Purchases.logLevel = .error
        Purchases.configure(withAPIKey: "appl_ukLcssJkMdgCvraYWRsnWlqegvP", appUserID: "DEBUG")

//        if let subscribe = ProcessInfo.processInfo.environment["SUBSCRIBED"], subscribe == "false" {
//            subscription = Subscription(isActive: false)
//            sync.set(false, for: keyID)
//        } else {
//            subscription = Subscription(isActive: true)
//            sync.set(true, for: keyID)
//        }

        subscription = .notActive
        sync.set(false, for: keyID)
    
//        subscription = .active
//        sync.set(true, for: keyID)

//        Task { @MainActor in
//            setup()
//        }
//
//        monitorChanges()

        NSUbiquitousKeyValueStore.default.synchronize()
        Purchases.shared.attribution.setAttributes(["ENVIRONMENT": "DEBUG"])
        return
#endif
        if UIApplication.shared.isRunningInTestFlightEnvironment() {
            Purchases.logLevel = .error
            Purchases.configure(withAPIKey: "appl_ukLcssJkMdgCvraYWRsnWlqegvP")
            subscription = Subscription(isActive: true)
            sync.set(true, for: keyID)
            Purchases.shared.attribution.setAttributes(["ENVIRONMENT": "TESTFLIGHT"])
            return
        }

        Purchases.logLevel = .error
        Purchases.configure(withAPIKey: "appl_ukLcssJkMdgCvraYWRsnWlqegvP")
        Purchases.shared.attribution.setAttributes(["ENVIRONMENT": "PRODUCTION"])
        
        Task { @MainActor in
            setup()
        }

        monitorChanges()
    }

    @MainActor
    private func setup() {
        Task {
            let customerInfo = try await Purchases.shared.customerInfo()
            if !customerInfo.activeSubscriptions.isEmpty {
                let subscriptionInfo = customerInfo.entitlements.active.values.first?.toSubscriptionInfo
                let newSubscription = Subscription(isActive: true, expiration: customerInfo.latestExpirationDate, info: subscriptionInfo)
                subscription = newSubscription
            } else if !customerInfo.nonSubscriptions.isEmpty {
                let subscriptionInfo = customerInfo.entitlements.active.values.first?.toSubscriptionInfo
                let newSubscription = Subscription(isActive: true, expiration: nil, info: subscriptionInfo)
                subscription = newSubscription
            } else {
                subscription = .notActive
            }
            subscriptionUpdated?(subscription)
        }
    }

    private func monitorChanges() {
        if UIApplication.shared.isRunningInTestFlightEnvironment() {
            return
        }

        subscriptionTask?.cancel()
        subscriptionTask = Task { @MainActor in
            for try await customerInfo in Purchases.shared.customerInfoStream {
                if !customerInfo.activeSubscriptions.isEmpty {
                    let subscriptionInfo = customerInfo.entitlements.active.values.first?.toSubscriptionInfo
                    let newSubscription = Subscription(isActive: true, expiration: customerInfo.latestExpirationDate, info: subscriptionInfo)
                    subscription = newSubscription
                } else if !customerInfo.nonSubscriptions.isEmpty {
                    let subscriptionInfo = customerInfo.entitlements.active.values.first?.toSubscriptionInfo
                    let newSubscription = Subscription(isActive: true, expiration: nil, info: subscriptionInfo)
                    subscription = newSubscription
                } else {
                    subscription = .notActive
                }
                subscriptionUpdated?(subscription)
            }
        }
    }

    @MainActor
    public func checkSubscription() async throws {
#if DEBUG
//        if let subscribe = ProcessInfo.processInfo.environment["SUBSCRIBED"], subscribe == "false" {
//            subscription = .notActive
//        }
        return
#endif
        if await UIApplication.shared.isRunningInTestFlightEnvironment() {
            subscription = .active
            return
        }

        let customerInfo = try await Purchases.shared.customerInfo()
        if !customerInfo.activeSubscriptions.isEmpty {
            let subscriptionInfo = customerInfo.entitlements.active.values.first?.toSubscriptionInfo
            let newSubscription = Subscription(isActive: true, expiration: customerInfo.latestExpirationDate, info: subscriptionInfo)
            subscription = newSubscription
        } else if !customerInfo.nonSubscriptions.isEmpty {
            let subscriptionInfo = customerInfo.entitlements.active.values.first?.toSubscriptionInfo
            let newSubscription = Subscription(isActive: true, expiration: nil, info: subscriptionInfo)
            subscription = newSubscription
        } else {
            subscription = .notActive
        }
        subscriptionUpdated?(subscription)
    }

}


extension UIApplication {

    // MARK: Public
    func isRunningInTestFlightEnvironment() -> Bool {
        if isSimulator() {
            return false
        } else {
            if isAppStoreReceiptSandbox() {
                return true
            } else {
                return false
            }
        }
    }

    func isRunningInAppStoreEnvironment() -> Bool {
        if isSimulator(){
            return false
        } else {
            if isAppStoreReceiptSandbox() || hasEmbeddedMobileProvision() {
                return false
            } else {
                return true
            }
        }
    }

    // MARK: Private
    private func hasEmbeddedMobileProvision() -> Bool {
        guard Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") == nil else {
            return true
        }
        return false
    }

    private func isAppStoreReceiptSandbox() -> Bool {
        if isSimulator() {
            return false
        } else {
#if targetEnvironment(macCatalyst) || os(macOS)
            return Bundle.main.isTestFlight
#else
            return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
#endif
        }
    }

    private func isSimulator() -> Bool {
#if arch(i386) || arch(x86_64)
        return true
#else
        return false
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
