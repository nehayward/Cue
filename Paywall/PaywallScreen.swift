import SwiftUI
import RevenueCat

struct PaywallScreen: View {
    @Environment(SubscriptionService.self) var subscriptionService: SubscriptionService
    @Environment(\.dismiss) var dismiss

    @State var offerings: Offerings?

    var body: some View {
        NavigationStack {
            VStack(alignment: .center) {
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
                    //                Text("\(Text("Free").bold()) for a month, then")
                    //                Text("$12.99 per year")
                    Text(offerings?.current?.monthly?.storeProduct.localizedPriceString ?? "")

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
                    guard let offerings, let annual = offerings.current?.monthly else { return }
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
            .padding()
            .fontDesign(.rounded)
            .task {
                offerings = try? await subscriptionService.getOfferings()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Super!")
                        .font(.title)
                        .foregroundStyle(Color.accentColor.gradient)
                        .scaledToFit()
                }
            }
        }
        .presentationDetents([.medium])
        .presentationCornerRadius(24)
    }
}

#Preview {
    Text("Pay Me Please")
        .sheet(isPresented: .constant(true)) {
            PaywallScreen()
                .environment(SubscriptionService())
        }

}
