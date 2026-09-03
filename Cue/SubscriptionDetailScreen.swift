import CloudStorage
import SwiftUI
import SonosKit
import RevenueCat
import SubscriptionKit
import RevenueCatUI

struct SubscriptionDetailScreen: View {
    @Environment(SubscriptionService.self) var subscriptionService: SubscriptionService
    @Environment(\.dismiss) var dismiss

    @State private var showManageSubscription: Bool = false
    @State private var showDiscount: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                if let info = subscriptionService.subscription.info {
                    LabeledContent {
                        Text(info.periodType.rawValue, format: .number)
                    } label: {
                        Text("Subscription Type")
                    }

                    LabeledContent {
                        Text(Date.now, style: .relative)
                    } label: {
                        Text("Member Since")
                    }

                    LabeledContent {
                        Text(Date.now, format: .dateTime)
                    } label: {
                        Text("Renewal Date")
                    }

                    LabeledContent {
                        Text(Date.now, format: .dateTime)
                    } label: {
                        Text("Renewal Date")
                    }
                } else {
                    LabeledContent {
                        Text(Date.now, style: .relative)
                    } label: {
                        Text("No active subscription")
                    }
                }

            }
            .overlay {
                Button {
                    showDiscount.toggle()
                    fetchCurrentProductAndOfferPromotion()
                } label: {
                    Text("Cancel")
                        .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Manage Subscription")
            .manageSubscriptionsSheet(isPresented: $showManageSubscription)
            .addDismiss {
                dismiss()
            }
        }
        .task {
            try? await subscriptionService.checkSubscription()
        }
    }

    func fetchCurrentProductAndOfferPromotion() {
        // Fetch current offerings
        Purchases.shared.getOfferings { (offerings, error) in
            guard let offerings = offerings, error == nil else {
                print("Error fetching offerings: \(error?.localizedDescription ?? "Unknown error")")
                return
            }

            // Get the current offering and product
            if let currentOffering = offerings.current, let currentProduct = currentOffering.availablePackages.last?.storeProduct {
                print("Current product: \(currentProduct)")
                print(currentProduct.discounts)
                print(currentProduct.subscriptionPeriod)
                Task {
                   let a = await Purchases.shared.eligiblePromotionalOffers(forProduct: currentProduct)
                    print(a)
                }
            } else {
                print("No current offering or product available")
            }
        }
    }

}


#Preview {
    SubscriptionDetailScreen()
        .environment(SubscriptionService.shared)
}

