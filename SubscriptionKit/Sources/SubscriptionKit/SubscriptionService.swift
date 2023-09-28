import UIKit
import WidgetKit
import Observation
import RevenueCat
import CloudStorage

@Observable
public final class SubscriptionService {
    static let key = "com.clic.subscriptions"
    private var subscriptionTask: Task<Void, Error>?
    private let sync = CloudStorageSync.shared
    public var current = SubscriptionServiceStorage()

    public init() {
        Purchases.logLevel = .error
        Purchases.configure(withAPIKey: "appl_ukLcssJkMdgCvraYWRsnWlqegvP")
//        current.subscription = Subscription(isActive: true,
//                                            expiration: Calendar.current.date(byAdding: .month, value: 1, to: .now)
//        )
        Task { @MainActor in
            setup()
        }
    }

    @MainActor
    private func setup() {
        Task {
            let customerInfo = try await Purchases.shared.customerInfo()
            if !customerInfo.activeSubscriptions.isEmpty {
                current.subscription = Subscription(isActive: true, expiration: customerInfo.latestExpirationDate)
            } else {
                current.subscription = .notActive
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
                    current.subscription = Subscription(isActive: true, expiration: customerInfo.latestExpirationDate)
                } else {
                    current.subscription = .notActive
                }
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}

extension SubscriptionService {
    public final class SubscriptionServiceStorage: ObservableObject {
        @CloudStorage(SubscriptionService.key) public var subscription: Subscription = .notActive 
    }
}
