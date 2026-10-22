import Foundation
import StoreKit

/// StoreKit's view of Super: what the App Store account owns, read on this
/// device. Each install's RevenueCat user is anonymous, so a device that never
/// restored (or whose RevenueCat user started over) reads as not subscribed
/// there though the account bought Super. StoreKit needs no restore, no network
/// and no RevenueCat user. The one file here that imports StoreKit.
enum StoreKitEntitlements {
    /// Super from the account's verified, unrevoked subscriptions and
    /// non-consumables; nil when it owns none.
    static func subscription() async -> Subscription? {
        var owned: [StoreKit.Transaction] = []
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  transaction.productType == .autoRenewable || transaction.productType == .nonConsumable
            else { continue }
            owned.append(transaction)
        }
        // Lifetime over any subscription, then the subscription that runs longest.
        let best = owned.first { $0.productType == .nonConsumable }
            ?? owned.max { ($0.expirationDate ?? .distantPast) < ($1.expirationDate ?? .distantPast) }
        guard let best else { return nil }
        let info = await SubscriptionInfo(best)
        return Subscription(isActive: true, expiration: best.expirationDate, info: info)
    }
}

private extension SubscriptionInfo {
    /// For a purchase only StoreKit knows about, so Settings still shows the
    /// plan and its renewal.
    init(_ transaction: StoreKit.Transaction) async {
        // A subscription renews unless StoreKit verifiably says it won't: an
        // unreadable status (offline, not verified) mustn't make a renewing
        // subscription's answer end with its period.
        var willRenew = transaction.productType == .autoRenewable
        if case .verified(let renewalInfo)? = await transaction.subscriptionStatus?.renewalInfo {
            willRenew = renewalInfo.willAutoRenew
        }
        var isTrial = false
        // tvOS named too: Cue (TV) links this package, whose manifest
        // declares no tvOS platform, so the check doesn't rest on whatever
        // tvOS target the package happens to be built for.
        if #available(iOS 17.2, macOS 14.2, tvOS 17.2, visionOS 1.1, *), let offer = transaction.offer {
            isTrial = offer.type == .introductory && offer.paymentMode == .freeTrial
        }
        self.init(
            productIdentifier: transaction.productID,
            isTrial: isTrial,
            willRenew: willRenew,
            expirationDate: transaction.expirationDate,
            unsubscribeDetectedAt: nil,
            billingIssueDetectedAt: nil
        )
    }
}
