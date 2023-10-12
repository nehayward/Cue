import SwiftUI
import WatchConnectivity
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
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                .onAppear {
                    print(Purchases.shared.appUserID)

                }
                .manageSubscriptionsSheet(isPresented: $showSubscriptions)


                Section {
                    Text(!sonosService.sonosPulse.isCancelled ? "Monitoring" : "Not found")
                } header: {
                    Text("Sonos System")
                }

                Section {
                    LabeledContent("ID", value: Purchases.shared.appUserID)
                        .textSelection(.enabled)
                        .scaledToFit()
                    LabeledContent("Watch App Installed", value: "\(WCSession.default.isWatchAppInstalled)")
                } header: {
                    Text("Profile")
                }

                Button {
                    let message = """
mailto:hi@clic.dance?subject=Support&body=\n\nVersion:\(String(describing: Bundle.main.infoDictionary?["CFBundleShortVersionString"]))\nID:\(Purchases.shared.appUserID)
"""
                    let url =  URL(string: message)!
                    UIApplication.shared.open(url) { (result) in
                        if result {
                           // The URL was delivered successfully!
                        }
                    }
                } label: {
                    Text("Support hi@clic.dance")
                }

            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .navigationTitle("Settings")
            #if DEBUG
            Text("DEBUG")
            #endif
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

