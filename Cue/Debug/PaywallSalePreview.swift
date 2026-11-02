#if DEBUG
import Foundation
import RevenueCat

/// A made-up sale to look at the paywall against, since a real one means
/// changing what App Store Connect sells: launch a Debug build with
/// `-dance.cue.paywallSalePreview YES` and the paywall shows this offering in
/// place of RevenueCat's. Monthly has three months at $0.99, yearly a first
/// year at half price, and the offering's metadata an eyebrow, a headline and a badge on
/// lifetime. Its plans can't be bought.
enum PaywallSalePreview {
    static let identifier = "sale preview"

    static var isOn: Bool {
        UserDefaults.standard.bool(forKey: "dance.cue.paywallSalePreview")
    }

    static var offering: Offering {
        Offering(
            identifier: identifier,
            serverDescription: "A made-up sale",
            metadata: ["eyebrow": "Launch special", "headline": "Half off your first year.", "badge": "Launch price", "badge_plan": "lifetime"],
            availablePackages: [
                package(.monthly, TestStoreProduct(
                    localizedTitle: "Monthly",
                    price: 1.99,
                    localizedPriceString: "$1.99",
                    productIdentifier: "com.super.cue.monthly",
                    productType: .autoRenewableSubscription,
                    localizedDescription: "Cue Super",
                    subscriptionPeriod: SubscriptionPeriod(value: 1, unit: .month),
                    introductoryDiscount: TestStoreProductDiscount(
                        identifier: "intro", price: 0.99, localizedPriceString: "$0.99", paymentMode: .payAsYouGo,
                        subscriptionPeriod: SubscriptionPeriod(value: 1, unit: .month), numberOfPeriods: 3, type: .introductory
                    )
                )),
                package(.annual, TestStoreProduct(
                    localizedTitle: "Yearly",
                    price: 14.99,
                    localizedPriceString: "$14.99",
                    productIdentifier: "com.super.cue.annual",
                    productType: .autoRenewableSubscription,
                    localizedDescription: "Cue Super",
                    subscriptionPeriod: SubscriptionPeriod(value: 1, unit: .year),
                    introductoryDiscount: TestStoreProductDiscount(
                        identifier: "intro", price: 7.49, localizedPriceString: "$7.49", paymentMode: .payUpFront,
                        subscriptionPeriod: SubscriptionPeriod(value: 1, unit: .year), numberOfPeriods: 1, type: .introductory
                    )
                )),
                package(.lifetime, TestStoreProduct(
                    localizedTitle: "Lifetime",
                    price: 39.99,
                    localizedPriceString: "$39.99",
                    productIdentifier: "com.cue.super.lifetime",
                    productType: .nonConsumable,
                    localizedDescription: "Cue Super"
                ))
            ],
            webCheckoutUrl: nil
        )
    }

    private static func package(_ type: PackageType, _ product: TestStoreProduct) -> Package {
        Package(
            identifier: "$rc_\(type == .annual ? "annual" : type == .monthly ? "monthly" : "lifetime")",
            packageType: type,
            storeProduct: product.toStoreProduct(),
            offeringIdentifier: identifier,
            webCheckoutUrl: nil
        )
    }
}
#endif
