import SwiftUI
import RevenueCat

struct PaywallScreen: View {
    @Environment(SubscriptionService.self) var subscriptionService: SubscriptionService
    @Environment(\.dismiss) var dismiss

    @State var offerings: Offerings?

    var body: some View {
        VStack(alignment: .center) {
            Text("Super!")
                .font(.title)
                .foregroundStyle(Color.accentColor.gradient)
                .scaledToFit()
            VStack {
                HStack {
                    Label("Unlimited Devices", systemImage: "hifispeaker.2.fill")
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(RoundedRectangle(cornerRadius: 24).foregroundStyle(.thinMaterial))
                HStack {
                    Label("Widgets", systemImage: "square.filled.on.square")
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(RoundedRectangle(cornerRadius: 24).foregroundStyle(.thinMaterial))
                HStack {
                    Label("Watch App", systemImage: "applewatch")
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(RoundedRectangle(cornerRadius: 24).foregroundStyle(.thinMaterial))
            }
            .padding()

            VStack {
                Text("\(Text("Free").bold()) for a month, then")
                Text("$12.99 per year")
                Text(offerings?.current?.annual?.storeProduct.localizedPriceString ?? "")
                Text(offerings?.current?.annual?.storeProduct.localizedDescription ?? "")

            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                Image(systemName: "circle.fill")
                    .font(.headline)
                    .padding(.leading)
                    .foregroundStyle(Color.accentColor.gradient)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 24).foregroundStyle(.thinMaterial))
            .padding(.bottom)


            Button {
//                subscriptionService.isEnabled = true
                guard let offerings, let annual = offerings.current?.annual else { return }
                Task {
                    do {
                        try await subscriptionService.pay(package: annual)
                    } catch {
                        print(error)
                    }
                }

            } label: {
                Text("Continue")
                    .font(.callout)
                    .bold()
                    .foregroundStyle(.ultraThickMaterial)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.plain)
            .fontDesign(.rounded)
            .sensoryFeedback(.success, trigger: subscriptionService.isEnabled == true)
            .background(Color.accentColor.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            HStack {
                Button("Terms of Use") {

                }
                Spacer()
                Button("Restore Purchases") {

                }
                Spacer()
                Button("Privacy Policy") {

                }
            }
            .padding()
            .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .presentationDetents([.fraction(0.7)])
        .presentationCornerRadius(24)
        .padding()
        .fontDesign(.rounded)
        .task {
            offerings = await try? subscriptionService.getOfferings()
        }


        //        SubscriptionStoreView(productIDs:  ["com.hackingwithswift.plus.subscription"])
        //            .storeButton(.visible, for: .restorePurchases, .redeemCode, .policies)
        //            .subscriptionStorePolicyDestination(for: .privacyPolicy) {
        //                Text("Privacy policy here")
        //            }
        //            .subscriptionStorePolicyDestination(for: .termsOfService) {
        //                Text("Terms of service here")
        //            }
        //            .subscriptionStoreControlStyle(.prominentPicker)
    }
}

#Preview {
    Text("Pay Me Please")
        .sheet(isPresented: .constant(true)) {
            PaywallScreen()
                .environment(SubscriptionService())
        }

}
