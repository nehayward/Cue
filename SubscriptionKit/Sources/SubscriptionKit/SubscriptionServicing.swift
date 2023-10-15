import Observation

public protocol SubscriptionServicing: Observable {
    var subscription: Subscription { get }
    func monitorChanges()
}
