import CloudStorage
import SwiftUI
import WatchConnectivity
import SonosKit
import RevenueCat
import SubscriptionKit
import RevenueCatUI


struct PreferenceScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(SubscriptionService.self) var subscriptionService: SubscriptionService
    @Environment(\.dismiss) var dismiss

    @State private var router = Router()
    @State private var showManageSubscriptions = false
    
    @AppStorage("AppIcon") var selectedAppIcon = "Default"
    @AppStorage("isCompact", store: UserDefaults(suiteName: "group.com.clic")) private var isCompact: Bool = false

    @CloudStorage("com.clic.autoLaunchNowPlaying")  private var autoLaunchNowPlaying: Bool = true

    var body: some View {
        @Bindable var sonosService = sonosService
        NavigationStack {
            Form {
                Section {
                    if !subscriptionService.subscription.isActive {
                        Button {
                            HapticManager.shared.fireHaptic(.buttonPress)
                        } label: {
                            PaywallButtonView()
                        }
                        .environment(router)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    } else {
                        VStack(alignment: .leading) {
                            Button {
                                HapticManager.shared.fireHaptic(.buttonPress)
                                showManageSubscriptions = true
//                                Telemetry.shared.send(event: .viewedManageSubscription)
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
                }
                Section {
                    Text(!sonosService.sonosPulse.isCancelled ? "Monitoring" : "Not found")
                    #if DEBUG
                    NavigationLink("Logs") {
                        LogScreen()
                    }

                    // MARK: Add multiple household ids
////                    Picker("HouseID", selection: $sonosService.houseID) {
//                    VStack {
//                        ForEach(Array(sonosService.houseIDs), id: \.self) {
//                            Text($0)
//                        }
//                    }
////                    }
                    #endif
                    if UIApplication.shared.isRunningInTestFlightEnvironment() {
                        NavigationLink("Logs") {
                            LogScreen()
                        }
                        Text("Vanished")
                        if let vanishes = sonosService.system?.vanished {
                            ForEach(vanishes) { vanish in
                                VStack(alignment: .leading) {
                                    Text(vanish.id)
                                    Text(vanish.name ?? "")
                                    if let lastSeen = vanish.lastSeen {
                                        Text(lastSeen, format: .dateTime)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Sonos System")
                }

                Section {
                    NavigationLink(value: RouterDestination.manageScenes) {
                        Text("Scenes")
                    }
                } footer: {
                    Text("Manage scenes")
                }

                // TODO: Add next release
                #if !targetEnvironment(macCatalyst)
                if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .pad {
                    Section {
                        Toggle(isOn: $isCompact) {
                            Text("Compact")
                        }
                        .tint(.accent)
                    } header: {
                        Text("Live Activities")
                    }
                }

                if UIDevice.current.userInterfaceIdiom == .phone {
                    Section {
                        Toggle(isOn: $autoLaunchNowPlaying) {
                            Text("Auto Launch Group")
                        }
                        .tint(.accent)
                    } header: {
                        Text("Watch")
                    } footer: {
                        Text("Instantly jump to the group currently playing.")
                    }
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

#endif
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
            .navigationTitle("Preferences")
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
//            .sheet(isPresented: $showSubscriptions) {
//                SubscriptionDetailScreen()
//                    .environment(subscriptionService)
//            }
            .withAppRouter(router: router)
            .withSheetDestinations(sheetDestinations: $router.presentedSheet)
            .addDismiss {
                dismiss()
            }
        }
        .task {
            try? await subscriptionService.checkSubscription()
        }
    }
}


#Preview {
    PreferenceScreen()
        .environment(SonosService.shared)
        .environment(SubscriptionService.shared)
}

