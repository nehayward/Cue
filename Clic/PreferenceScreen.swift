import SwiftUI
import WatchConnectivity
import SonosKit
import RevenueCat
import SubscriptionKit
import RevenueCatUI

struct PreferenceScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(SubscriptionService.self) var subscriptionService: SubscriptionService

    @State private var showPaywall = false
    @State private var showSubscriptions = false
    @AppStorage("AppIcon") var selectedAppIcon = "Default"

    private let impactFeedbackGenerator = UIImpactFeedbackGenerator()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !subscriptionService.subscription.isActive {
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
                            if let expiration = subscriptionService.subscription.expiration {
                                Text("Expiring \(Text(expiration, style: .date))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        Purchases.shared.presentCodeRedemptionSheet()
                    } label: {
                        Text("Promo Code")
                    }
                }
                .manageSubscriptionsSheet(isPresented: $showSubscriptions)

                Section {
                    Text(!sonosService.sonosPulse.isCancelled ? "Monitoring" : "Not found")
                    #if DEBUG
                    NavigationLink("Logs") {
                        LogScreen()
                    }
                    #endif
                } header: {
                    Text("Sonos System")
                }

                Section {
                    NavigationLink {
                        ManageSceneScreen()
                    } label: {
                        Text("Scenes")
                    }
                } footer: {
                    Text("Manage scenes")
                }

//                Section {
//                    Picker(selection: $selectedAppIcon, label: EmptyView()) {
//                        ForEach( Bundle.main.iconFileNames, id: \.self) { name in
//                            HStack {
//                                Image(uiImage: UIImage(named: name)!)
//                                    .resizable(resizingMode: .stretch)
//                                    .frame(width: 64, height: 64)
//                                    .cornerRadius(16)
//                                VStack(alignment: .leading) {
//                                    Text(name)
//                                    Link("By SH Creative", destination: URL(string: "https://www.shcreative.io")!)
//                                }
//                                Spacer()
//                            }
//                        }
//                    }
//                    .pickerStyle(.navigationLink)
//                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
//                    .onChange(of: selectedAppIcon) { oldValue, newValue in
//                        if newValue == "Default" {
//                            UIApplication.shared.setAlternateIconName(nil)
//                            return
//                        }
//                        UIApplication.shared.setAlternateIconName(newValue) { (error) in
//                            if let error = error {
//                                print("Failed request to update the app’s icon: \(error)")
//                            }
//                        }
//                    }
//                } header: {
//                    Text("Customize")
//                }

                Section {
                    if let name = Bundle.main.iconFileNames.first {
                        HStack {
                            Image(uiImage: UIImage(named: name)!)
                                .resizable(resizingMode: .stretch)
                                .frame(width: 64, height: 64)
                                .cornerRadius(16)
                            VStack(alignment: .leading) {
                                Text(name)
                                Link("By SH Creative", destination: URL(string: "https://www.shcreative.io")!)
                            }
                            Spacer()
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    }
                } header: {
                    Text("Personalize")
                }

                Section {
                    let message = "mailto:hi@clic.dance?subject=Support&body=\n\nVersion: \(OSEnvironment.versionInfo)\nID: \(Purchases.shared.appUserID)"
                    Link("Support hi@clic.dance", destination: URL(string: message)!)
                } footer: {
                    VStack(alignment: .center) {
                        Text("Version **\(OSEnvironment.versionInfo)**")
                        Text(Purchases.shared.appUserID)
                            .textSelection(.enabled)
                            .scaledToFit()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .navigationTitle("Preferences")
        }
        .task {
            try? await subscriptionService.checkSubscription()
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

