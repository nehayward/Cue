import Analytics
import CloudStorage
import Defaults
import SwiftUI
import WatchConnectivity
import SonosKit
import RevenueCat
import MusicSearchKit
import SubscriptionKit
import RevenueCatUI
import MessageUI

struct PreferenceScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(SubscriptionService.self) var subscriptionService: SubscriptionService
    @Environment(\.dismiss) var dismiss

    @State private var betaFeatures = BetaFeatures()
    @State private var router = Router()
    @State private var showManageSubscriptions = false
    @State private var isShowingMailView = false

    @AppStorage("AppIcon") var selectedAppIcon = "Default"
    @AppStorage("isCompact", store: UserDefaults(suiteName: "group.com.clic")) private var isCompact: Bool = false
    @AppStorage(AppStorageKeys.mediaService) private var musicSearchSelection: MediaSearchService = .apple

    @CloudStorage("com.clic.autoLaunchNowPlaying")  private var autoLaunchNowPlaying: Bool = true

    var body: some View {
        @Bindable var sonosService = sonosService
        NavigationStack {
            Form {
                Section {
                    if !subscriptionService.subscription.isActive {
                        PaywallButtonView()
                            .environment(router)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    } else {
                        VStack(alignment: .leading) {
                            Button {
                                HapticManager.shared.fireHaptic(.buttonPress)
                                showManageSubscriptions = true
                                Analytics.shared.track(.viewedManageSubscription)
                            } label: {
                                Text("Manage Subscription")
                            }
                            if let info = subscriptionService.subscription.info, let expiration = info.expirationDate {
                                if info.willRenew {
                                    Text("Renews \(Text(expiration, style: .date))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Expiring \(Text(expiration, style: .date))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if UIApplication.shared.isRunningInTestFlightEnvironment() {
                    Section {
                        NavigationLink("Logs") {
                            LogScreen()
                        }
                        Button("Send Logs") {
                            self.isShowingMailView = true
                        }
                        .sheet(isPresented: $isShowingMailView) {
                            MailViewRepresentable(
                                subject: "Support Logs",
                                recipients: ["hi@clic.dance"],
                                messageBody: "Version: \(OSEnvironment.versionInfo)\nID: \(Purchases.shared.appUserID)",
                                logFilesDirectory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appending(path: "Logs")
                            )
                        }
                        if let vanishes = sonosService.system?.vanished {
                            Text("Vanished")
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
                    } header: {
                        Text("Debug 👾")
                    }
                }

                Section {
                    Toggle(isOn: $betaFeatures.tidalFeature) {
                        HStack {
                            MediaSearchService.tidal.icon
                                .frame(width: 24, height: 24)
                            Text(MediaSearchService.tidal.title)
                        }
                    }
                    .tint(.accent)
                    .onChange(of: betaFeatures.tidalFeature) {
                        musicSearchSelection = betaFeatures.tidalFeature ? .tidal : .apple
                    }
                } header: {
                    Text("Beta Features")
                } footer: {
                    Text("Requires Clic Super Subscription")
                }
                .disabled(!subscriptionService.subscription.isActive)

                Section {
                    Text(!sonosService.sonosPulse.isCancelled ? "Monitoring" : "Not found")
                    Button {
                        Task {
                            await sonosService.refreshLibrary()
                        }
                    } label: {
                        Label("Refresh Library", systemImage: "arrow.clockwise.square.fill")
                    }

                    NavigationLink(value: RouterDestination.alarms) {
                        Label("Alarms", systemImage: "alarm.fill")
                            .foregroundStyle(.primary)
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
#if !targetEnvironment(macCatalyst) && !os(visionOS)
                if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .pad {
                    Section {
                        Toggle(isOn: $isCompact) {
                            Text("Compact")
                            Text("Removes volumes controls and overall size of Live Activites")
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

                // MARK: Disable until fixed later for app review.
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
                //                                        .foregroundStyle(.primary)
                //                                    Text("By SH Creative")
                //                                        .foregroundStyle(.secondary)
                //                                }
                //                                Spacer()
                //                            }.contextMenu {
                //                                Link("By SH Creative", destination: URL(string: "https://www.shcreative.io")!)
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
                //                    .overlay {
                //                        if !subscriptionService.subscription.isActive {
                //                            Text("Subscribe to Customize")
                //                                .fontDesign(.rounded)
                //                                .bold()
                //                                .padding()
                //                                .background(.thinMaterial)
                //                                .clipShape(RoundedRectangle(cornerRadius: 12))
                //                        }
                //                    }
                //                } header: {
                //                    Text("Customize")
                //                }
                //                .disabled(!subscriptionService.subscription.isActive)
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
            .fontDesign(.rounded)
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

