import RevenueCatUI
import RevenueCat
import SwiftUI

struct PaywallView_Previews: PreviewProvider {
    private static let product = TestStoreProduct(
        localizedTitle: "Monthly",
        price: 1.99,
        localizedPriceString: "$4.99",
        productIdentifier: "$rc_monthly",
        productType: .autoRenewableSubscription,
        localizedDescription: "A product description."
    )

    private static let offering = Offering(
        identifier: Self.offeringIdentifier,
        serverDescription: "Yearly",
        metadata: [:],
        availablePackages: [
            .init(
                identifier: "com.super.clic.monthly",
                packageType: .monthly,
                storeProduct: Self.product.toStoreProduct(),
                offeringIdentifier: Self.offeringIdentifier
            )
        ]
    )

    private static let offeringIdentifier = "default"

    static var previews: some View {
        PaywallView(offering: offering, displayCloseButton: true)
    }
}
