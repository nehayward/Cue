import CloudStorage
import CloudKit
import UIKit
import WidgetKit
import Observation
import RevenueCat

@Observable
public final class SubscriptionService: SubscriptionServicing {
    private var subscriptionTask: Task<Void, Error>?
    private let sync = CloudStorageSync.shared
    public var subscription: Subscription = .notActive
    private let identifierKey = "com.clic.identifier"

    public init() {
#if DEBUG
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: "appl_ukLcssJkMdgCvraYWRsnWlqegvP", appUserID: "DEBUG")
        subscription = Subscription(isActive: true)
        sync.set(true, for: "com.clic.subscriptions")
        Purchases.shared.attribution.setAttributes(["ENVIRONMENT": "DEBUG"])
        return
#endif
        if UIApplication.shared.isRunningInTestFlightEnvironment() {
            Purchases.logLevel = .error
            Purchases.configure(withAPIKey: "appl_ukLcssJkMdgCvraYWRsnWlqegvP")
            subscription = Subscription(isActive: true)
            sync.set(true, for: "com.clic.subscriptions")
            Purchases.shared.attribution.setAttributes(["ENVIRONMENT": "TESTFLIGHT"])
            login()
            return
        }

        Purchases.logLevel = .error
        Purchases.configure(withAPIKey: "appl_ukLcssJkMdgCvraYWRsnWlqegvP")
        Purchases.shared.attribution.setAttributes(["ENVIRONMENT": "PRODUCTION"])
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
        return
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
#if DEBUG
        return
#endif
        if await UIApplication.shared.isRunningInTestFlightEnvironment() {
            return
        }


        let customerInfo = try await Purchases.shared.customerInfo()
        if !customerInfo.activeSubscriptions.isEmpty {
            let newSubscription = Subscription(isActive: true, expiration: customerInfo.latestExpirationDate)
            subscription = newSubscription
        } else {
            subscription = .notActive
        }
    }

    func login() {
        Task {
            if let id = sync.string(for: identifierKey) {
                guard let (_, created) = try? await Purchases.shared.logIn(id) else { return }
                print(created)
                return
            }
            guard let id = await UIDevice.current.identifierForVendor?.uuidString else {
                print("No ID")
                return
            }
            guard let (_, created) = try? await Purchases.shared.logIn(id) else { return }
            if created {
                sync.set(id, for: identifierKey)
                NSUbiquitousKeyValueStore.default.synchronize()
            }
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
