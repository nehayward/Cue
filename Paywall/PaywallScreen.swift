import SwiftUI

struct PaywallScreen: View {
    @Environment(SuperMember.self) var superMember: SuperMember
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .center) {
            Text("Super!")
            Text("Start a 1 month trial now to unlock the unlimited devices, Widgets, Watch App, and more!")
                .multilineTextAlignment(.center)
            Button {
                superMember.isEnabled = true
                dismiss()
            } label: {
                Text("Start trial")
                    .font(.title)
                    .bold()
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.plain)
            .fontDesign(.rounded)
            .sensoryFeedback(.success, trigger: superMember.isEnabled == true)
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
        .presentationDetents([.medium])
        .padding()


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
                .environment(SuperMember())
        }

}
