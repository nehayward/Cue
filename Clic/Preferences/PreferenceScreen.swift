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
    @Environment(\.dismiss) var dismiss

    @Environment(SonosService.self) var sonosService
    @Environment(SubscriptionService.self) var subscriptionService
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(AlertService.self) var alertService


    @State private var coreFeatures = CoreFeatures()
    @State private var router = Router()
    @State private var showManageSubscriptions = false
    @State private var isShowingMailView = false
    @State private var refreshSonosLibrary = false

    @AppStorage("AppIcon") private var selectedAppIcon = "Default"
    @AppStorage("isCompact", store: UserDefaults(suiteName: "group.com.clic")) private var isCompact: Bool = false

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
                    LabeledContent("System") {
                        Text(!sonosService.sonosPulse.isCancelled ? "Monitoring" : "Not found")
                    }
                    NavigationLink(value: RouterDestination.houseHold) {
                        Label("Households", systemImage: "house")
                            .foregroundStyle(.primary)
                    }
                    NavigationLink(value: RouterDestination.speakerSettingsList) {
                        Label("Speaker Settings", systemImage: "hifispeaker")
                            .foregroundStyle(.primary)
                    }
                    NavigationLink(value: RouterDestination.alarms) {
                        Label("Alarms", systemImage: "alarm")
                            .foregroundStyle(.primary)
                    }
                    
                    Button {
                        Task {
                            alertService.showAlert(with: "Refreshing Sonos Library", imageName: "arrow.clockwise.circle")
                            await sonosService.refreshLibrary()
                        }
                    } label: {
                        Label {
                            Text("Refresh Sonos Library")
                        } icon: {
                            Image(systemName: "arrow.clockwise.circle")
                        }
                    }
                } header: {
                    Text("Sonos System")
                }
                Section {
                    NavigationLink {
                        List {
                            Section {
                                ForEach(MediaSearchService.allCases, id: \.self) { service in
                                    Toggle(isOn: coreFeatures.enabledServices(service)) {
                                        Label {
                                            Text(service.title)
                                        } icon: {
                                            service.iconForMusicService
                                                .frame(width: 24, height: 24)
                                        }
                                    }
                                    .tint(.accent)
                                }
                            } header:  {
                                Text("Supported Services")
                            } footer: {
                                Text("Requires authorization in the Sonos app.")
                            }

                            Section {
                                Button {
                                    router.presentedSheet = .plexManagement
                                } label: {
                                    Label {
                                        HStack {
                                            Text(MediaSearchService.plex.title)
                                            Spacer()
                                            if musicSearchService.isPlexAuthorized {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.green.gradient)
                                            } else {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.red.gradient.secondary)
                                            }
                                        }
                                    } icon: {
                                        MediaSearchService.plex.iconForMusicService
                                            .frame(width: 20, height: 20)
                                    }
                                }
                            } header:  {
                                Text("Personalized Services")
                            } footer: {
                                Text("Requires authorization in the **Sonos app** and **Clic**")
                            }

                            Toggle(isOn: $coreFeatures.nowPlaying) {
                                HStack {
                                    Image(.nowPlayingAppIcon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 24, height: 24)
                                    VStack(alignment: .leading) {
                                        Link("Now Playing", destination: URL(string: "https://nowplaying.page")!)
                                        Text("Add option to open current track in the Now Playing app.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tint(.accent)
                        }
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LabeledContent {
                            ForEach(MediaSearchService.allCases, id: \.self) { service in
                                if coreFeatures.enabledServices(service).wrappedValue {
                                    service.iconForMusicService
                                        .frame(width: 20, height: 20)
                                }
                            }
                        } label: {
                            Text("Services")
                        }
                    }
                    NavigationLink(value: RouterDestination.manageScenes) {
                        LabeledContent("Scenes") {
                            Text("Manage scenes")
                        }
                    }
#if !targetEnvironment(macCatalyst) && !os(visionOS)
                    if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .pad {
                        Toggle(isOn: $isCompact) {
                            Text("Compact Live Activities")
                            Text("Removes volumes controls and reduces size of Live Activities")
                        }
                        .tint(.accent)
                    }

                    if UIDevice.current.userInterfaceIdiom == .phone {
                        Toggle(isOn: $autoLaunchNowPlaying) {
                            Text("Auto launch to Group/Room playing on watch")
                            Text("Instantly jump to the group currently playing.")
                        }
                        .tint(.accent)
                    }
#endif
                }


//                Section {
//                    Toggle(isOn: $betaFeatures.tidalFeature) {
//                        HStack {
//                            MediaSearchService.tidal.icon
//                                .frame(width: 24, height: 24)
//                            VStack(alignment: .leading) {
//                                Text(MediaSearchService.tidal.title)
//                                Text("Search and play songs, albums, and artists (requires Tidal authorization in the Sonos app).")
//                                    .font(.caption)
//                                    .foregroundStyle(.secondary)
//                            }
//                        }
//                    }
//                    .tint(.accent)
//                    .onChange(of: betaFeatures.tidalFeature) {
//                        musicSearchSelection = betaFeatures.tidalFeature ? .tidal : .apple
//                    }
//                } header: {
//                    Text("Beta 👾")
//                } footer: {
//                    Text("Requires Subscription")
//                }
//                .disabled(!subscriptionService.subscription.isActive)

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
                Section {
                    let message = "mailto:hi@clic.dance?subject=Support&body=\n\nVersion: \(OSEnvironment.versionInfo)\nID: \(Purchases.shared.appUserID)"
                    Link("Support hi@clic.dance", destination: URL(string: message)!)
                        .tint(.accent)
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
            .navigationBarTitleDisplayMode(.inline)
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
        .withAlert()
        .animation(.spring, value: alertService.alert.isShowing)
        .task {
            try? await subscriptionService.checkSubscription()
        }
    }
}


#Preview {
    Text("Preference")
        .sheet(isPresented:.constant(true)) {
            PreferenceScreen()
                .environment(SonosService.shared)
                .environment(SubscriptionService.shared)
        }

}
