import UIKit
import WidgetKit
import Observation
import RevenueCat
import CloudStorage

protocol SubscriptionServicing  {
    func monitorChanges()
}

@Observable
public final class SubscriptionService: SubscriptionServicing {
    static let key = "com.clic.subscriptions"
    private var subscriptionTask: Task<Void, Error>?
    private let sync = CloudStorageSync.shared
    public var subscription: Subscription = .notActive
    public var isActive: Bool {
        get {
            sync.bool(for: Self.key) ?? false
        }
        set {
            sync.set(newValue, for: Self.key)
        }
    }

    public init() {
        Purchases.logLevel = .error
        Purchases.configure(withAPIKey: "appl_ukLcssJkMdgCvraYWRsnWlqegvP")
        Task { @MainActor in
            setup()
        }
//        #if DEBUG
//        enable()
//        #endif
    }

    @MainActor
    private func setup() {
        Task {
            let customerInfo = try await Purchases.shared.customerInfo()
            if !customerInfo.activeSubscriptions.isEmpty {
                let newSubscription = Subscription(isActive: true, expiration: customerInfo.latestExpirationDate)
                subscription = newSubscription
                isActive = true
            } else {
                subscription = .notActive
                isActive = false
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @MainActor
    public func monitorChanges() {
        subscriptionTask?.cancel()
        subscriptionTask = Task {
            for try await customerInfo in Purchases.shared.customerInfoStream {
                if !customerInfo.activeSubscriptions.isEmpty {
                    subscription = Subscription(isActive: true, expiration: customerInfo.latestExpirationDate)
                    isActive = true
                } else {
                    subscription = .notActive
                    isActive = false
                }
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    private func enable() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(4)) { [weak self] in
            self?.subscription = Subscription(isActive: true, expiration: Calendar.current.date(byAdding: .month, value: 1, to: .now))
        }
    }
}
