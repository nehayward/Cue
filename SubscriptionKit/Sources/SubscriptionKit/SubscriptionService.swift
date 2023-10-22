import UIKit
import WidgetKit
import Observation
import RevenueCat
import CloudStorage

@Observable
public final class SubscriptionService: SubscriptionServicing {
    private var subscriptionTask: Task<Void, Error>?
    private let sync = CloudStorageSync.shared
    public var subscription: Subscription = .notActive

    public init() {
#if DEBUG
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: "appl_ukLcssJkMdgCvraYWRsnWlqegvP", appUserID: "DEBUG")
        if ProcessInfo.processInfo.environment["Super"]?.lowercased() == "true" {
            subscription = Subscription(isActive: true)
            sync.set(true, for: "com.clic.subscriptions")
        }
        return
#endif
        if UIApplication.shared.isRunningInTestFlightEnvironment() {
            Purchases.logLevel = .error
            Purchases.configure(withAPIKey: "appl_ukLcssJkMdgCvraYWRsnWlqegvP", appUserID: "TESTFLIGHT")
            subscription = Subscription(isActive: true)
            sync.set(true, for: "com.clic.subscriptions")
            return
        }

        Purchases.logLevel = .error
        Purchases.configure(withAPIKey: "appl_ukLcssJkMdgCvraYWRsnWlqegvP")
        Task { @MainActor in
            setup()
        }
    }

    @MainActor
    private func setup() {
        Task {
            let customerInfo = try await Purchases.shared.customerInfo()
            if !customerInfo.activeSubscriptions.isEmpty {
                let newSubscription = Subscription(isActive: true, expiration: customerInfo.latestExpirationDate)
                subscription = newSubscription
            } else {
                subscription = .notActive
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @MainActor
    public func monitorChanges() {
#if DEBUG
        if ProcessInfo.processInfo.environment["Super"]?.lowercased() == "true" {
            return
        }
#endif
        if UIApplication.shared.isRunningInTestFlightEnvironment() {
            return
        }

        subscriptionTask?.cancel()
        subscriptionTask = Task {
            for try await customerInfo in Purchases.shared.customerInfoStream {
                if !customerInfo.activeSubscriptions.isEmpty {
                    subscription = Subscription(isActive: true, expiration: customerInfo.latestExpirationDate)
                } else {
                    subscription = .notActive
                }
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    public func checkSubscription() async throws {
        let customerInfo = try await Purchases.shared.customerInfo()
        if !customerInfo.activeSubscriptions.isEmpty {
            let newSubscription = Subscription(isActive: true, expiration: customerInfo.latestExpirationDate)
            subscription = newSubscription
        } else {
            subscription = .notActive
        }
    }

    private func enable() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(4)) { [weak self] in
            self?.subscription = Subscription(isActive: true, expiration: Calendar.current.date(byAdding: .month, value: 1, to: .now))
        }
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
            guard let url = Bundle.main.appStoreReceiptURL else {
                return false
            }
            guard url.lastPathComponent == "sandboxReceipt" else {
                return false
            }
            return true
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
