import Foundation
import RevenueCat

public class Subscription: Codable, Equatable {
    public var isActive: Bool
    public var expiration: Date?
    public var info: SubscriptionInfo?

    public init(isActive: Bool, expiration: Date? = nil, info: SubscriptionInfo? = nil) {
        self.isActive = isActive
        self.expiration = expiration
        self.info = info
    }

    public static func == (lhs: Subscription, rhs: Subscription) -> Bool {
        lhs.isActive == rhs.isActive &&
        lhs.expiration == rhs.expiration
    }
}

extension Subscription {
    public static var active = Subscription(isActive: true, expiration: .distantFuture)
    public static var notActive = Subscription(isActive: false)

    /// The end of the current period; nil for Lifetime. The entitlement's own
    /// when there is one: with Lifetime and a subscription both bought, it's
    /// Lifetime's (none), while `expiration` is the subscription's.
    public var periodEnd: Date? {
        if let info = info {
            return info.expirationDate
        }
        return expiration
    }

    /// How long this answer holds without asking again. Lifetime, and a
    /// subscription that renews, until told otherwise: never lock out someone
    /// who's paying because Cue hasn't run since a renewal. One that won't
    /// renew, until its period ends. Nil when not active.
    public var activeUntil: Date? {
        guard isActive else { return nil }
        if let info = info, info.endsWithPeriod, let end = periodEnd {
            return end
        }
        return .distantFuture
    }
}


/// What Cue reads of the plan behind Super: RevenueCat's entitlement, or the
/// StoreKit transaction when only StoreKit knows of the purchase.
public struct SubscriptionInfo: Codable {
    public let productIdentifier: String
    /// A free trial: it renews into the plan unless cancelled first.
    public let isTrial: Bool
    public let willRenew: Bool
    /// The end of the current period; nil for Lifetime.
    public let expirationDate: Date?
    public let unsubscribeDetectedAt: Date?
    public let billingIssueDetectedAt: Date?

    /// Whether Super ends with this period: cancelled, or never renewing (a
    /// promotion). Not a billing problem, though RevenueCat turns `willRenew`
    /// off for one too: Apple keeps retrying, and a fixed card renews it
    /// without Cue running.
    var endsWithPeriod: Bool {
        unsubscribeDetectedAt != nil || (!willRenew && billingIssueDetectedAt == nil)
    }
}

extension EntitlementInfo {
    var toSubscriptionInfo: SubscriptionInfo {
        SubscriptionInfo(
            productIdentifier: productIdentifier,
            isTrial: periodType == .trial,
            willRenew: willRenew,
            expirationDate: expirationDate,
            unsubscribeDetectedAt: unsubscribeDetectedAt,
            billingIssueDetectedAt: billingIssueDetectedAt
        )
    }
}
