import SwiftUI
import SonosKit
import RevenueCat
import SubscriptionKit
import RevenueCatUI

struct PreferenceScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(SubscriptionService.self) var subscriptionService: SubscriptionService

    @State var showPaywall = false
    @State var showSubscriptions = false

    private let impactFeedbackGenerator = UIImpactFeedbackGenerator()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !subscriptionService.current.subscription.isActive {
                        Button {
                            impactFeedbackGenerator.impactOccurred()
                            showPaywall = true
                        } label: {
                            Text("Subscribe")
                                .frame(maxWidth: .infinity)
                                .bold()
                                .foregroundStyle(.ultraThickMaterial)
                                .padding()
                        }
                        .fontDesign(.rounded)
                        .background(Color.accentColor.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    } else {
                        VStack(alignment: .leading) {
                            Button {
                                showSubscriptions = true
                            } label: {
                                Text("Manage Subscription")
                            }
                            if let expiration = subscriptionService.current.subscription.expiration {
                                Text("Expiring \(Text(expiration, style: .date))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .manageSubscriptionsSheet(isPresented: $showSubscriptions)


                Section {
                    Text(!sonosService.sonosPulse.isCancelled ? "Monitoring" : "Not found")
                } header: {
                    Text("Sonos System")
                }

            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .navigationTitle("Settings")
        }
        .task {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" else { return }
            sonosService.monitor()
            impactFeedbackGenerator.prepare()
        }
    }
}


#Preview {
    PreferenceScreen()
        .environment(SonosService())
        .environment(SubscriptionService())
}

