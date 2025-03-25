import Analytics
import CloudStorage
import Defaults
import SwiftUI
import SonosKit
import RevenueCat
import MusicSearchKit
import SubscriptionKit
import RevenueCatUI

struct PreferenceScreen: View {
    @Environment(\.dismiss) var dismiss
    
    @Environment(SonosService.self) var sonosService
    @Environment(SubscriptionService.self) var subscriptionService
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(AlertService.self) var alertService
    @Environment(CoreFeatures.self) var coreFeatures

    var destination: RouterDestination? = nil
    
    @State private var router = Router()
    @State private var showManageSubscriptions = false
    @State private var isShowingMailView = false
    @State private var refreshSonosLibrary = false
    
    @AppStorage("AppIcon") private var selectedAppIcon = "Default"
    @AppStorage("isCompact", store: UserDefaults(suiteName: "group.com.clic")) private var isCompact: Bool = false
    @AppStorage("ClicMiniEnabled") private var isMenuBarAppEnabled: Bool = true
    
    @AppStorage(Defaults.AppStorageKeys.colorScheme) private var colorScheme: ColorSchemePreference = .system
    @AppStorage(Defaults.AppStorageKeys.speedLaunchNowPlaying) private var speedLaunchNowPlaying: Bool = false
    
    @CloudStorage("com.clic.autoLaunchNowPlaying") private var autoLaunchNowPlaying: Bool = true
    
#if targetEnvironment(macCatalyst)
    @State private var menuAppLaunchAtLoginManager = MenuAppLaunchAtLoginManager.shared
#endif
    
    var body: some View {
        @Bindable var sonosService = sonosService
        @Bindable var coreFeatures = coreFeatures

        NavigationStack(path: $router.path) {
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
                                Label {
                                    Text("Clic Super")
                                } icon: {
                                    Image("clic.icon")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .foregroundStyle(.white)
                                        .padding(8)
                                        .frame(width: 32, height: 32)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .foregroundStyle(.black)
                                        )
                                }
                            }
                            .tint(.primary)
                            
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
                } header: {
                    Spacer(minLength: 0).listRowInsets(EdgeInsets())
                }
                
//                if UIApplication.shared.isRunningInTestFlightEnvironment() {
//                    Section {
//                        NavigationLink("Logs") {
//                            LogScreen()
//                        }
//                        if let vanishes = sonosService.system?.vanished {
//                            Text("Vanished")
//                            ForEach(vanishes) { vanish in
//                                VStack(alignment: .leading) {
//                                    Text(vanish.id)
//                                    Text(vanish.name ?? "")
//                                    if let lastSeen = vanish.lastSeen {
//                                        Text(lastSeen, format: .dateTime)
//                                    }
//                                }
//                            }
//                        }
//                    } header: {
//                        Text("Debug 👾")
//                    }
//
//                    PaywallButtonView()
//                        .environment(router)
//                        .listRowBackground(Color.clear)
//                        .listRowInsets(EdgeInsets())
//                }
                
                Section {
                    Label {
                        HStack {
                            Text(!sonosService.sonosPulse.isCancelled ? "Monitoring" : "Not found")
                            Spacer()
                            Image(systemName: "circle.fill")
                                .font(.caption2)
                                .foregroundStyle(!sonosService.sonosPulse.isCancelled ? .green : .red)
                                .shadow(color: !sonosService.sonosPulse.isCancelled ? .green : .red, radius: 2, x: 0, y: 0)
                        }
                    } icon: {
                        Image(systemName: "wifi")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white)
                            .padding(8)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .foregroundStyle(.black)
                            )
                    }
                    
                    NavigationLink(value: RouterDestination.speakerSettingsList) {
                        Label {
                            Text("Speaker Settings")
                        } icon: {
                            Image(systemName: "hifispeaker.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .foregroundStyle(.black)
                                )
                        }
                    }
                    
                    NavigationLink(value: RouterDestination.alarms) {
                        Label {
                            Text("Alarms")
                        } icon: {
                            Image(systemName: "alarm.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .foregroundStyle(.orange)
                                )
                        }
                    }
                    
                    NavigationLink(value: RouterDestination.houseHold) {
                        Label {
                            Text("Switch Households")
                        } icon: {
                            Image(systemName: "house.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .foregroundStyle(.blue)
                                )
                        }
                    }
                    
                    Button {
                        Task {
                            alertService.showAlert(with: "Refreshing Sonos Library", imageName: "arrow.clockwise")
                            await sonosService.refreshLibrary()
                        }
                    } label: {
                        Label {
                            Text("Refresh Sonos Library")
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .bold()
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .foregroundStyle(.blue)
                                )
                        }
                    }
                    .tint(.primary)
                }
                
                
            #if targetEnvironment(macCatalyst)
                Section {
                    Label {
                        HStack {
                            Text("Clic Mini (Menu Bar App)")
                            Spacer()
                            Image(systemName: "circle.fill")
                                .font(.caption2)
                                .foregroundStyle(menuAppLaunchAtLoginManager.isRunning ? .green : .red)
                                .shadow(color: menuAppLaunchAtLoginManager.isRunning ? .green : .red, radius: 2, x: 0, y: 0)
                        }
                        .animation(.spring, value: menuAppLaunchAtLoginManager.isRunning)
                    } icon: {
                        Image(systemName: "hifispeaker.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white)
                            .bold()
                            .padding(8)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .foregroundStyle(.blue)
                            )
                    }
                    Button {
                        menuAppLaunchAtLoginManager.macUtils?.openClicMiniApp()
                    } label: {
                        Label {
                            Text("Open Clic Mini (Menu Bar App) when Clic Opens")
                            Spacer()
                            Toggle(isOn: $isMenuBarAppEnabled) {
                                Text("Enable Clic Mini")
                            }
                            .tint(.accent)
                            .labelsHidden()
                            .onChange(of: isMenuBarAppEnabled) {
                                if isMenuBarAppEnabled {
                                    menuAppLaunchAtLoginManager.macUtils?.openClicMiniApp()
                                }
                            }
                        } icon: {
                            Image(systemName: "arrow.up.forward")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .bold()
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .foregroundStyle(Color.cyan)
                                )
                        }
                    }
                    .tint(.primary)
                }
                #endif
                colorSchemeSection
                Section {
                    NavigationLink(value: RouterDestination.servicePreferenceScreen) {
                        LabeledContent {
                            ForEach(MediaSearchService.allCases, id: \.self) { service in
                                if coreFeatures.enabledServices(service).wrappedValue {
                                    service.iconForMusicService
                                        .frame(width: 20, height: 20)
                                }
                            }
                        } label: {
                            Label {
                                Text("Services")
                            } icon: {
                                Image(systemName: "music.quarternote.3")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.white)
                                    .bold()
                                    .padding(8)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .foregroundStyle(.accent)
                                    )
                            }
                        }
                    }
                    NavigationLink(value: RouterDestination.manageScenes) {
                        Label {
                            HStack {
                                Text("Scenes")
                                Spacer()
                                Text("Super")
                                    .font(.caption)
                                    .textCase(.uppercase)
                                    .padding(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(.secondary, lineWidth: 1)
                                    )
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bolt.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .bold()
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .foregroundStyle(Color.teal)
                                )
                        }
                    }.disabled(!subscriptionService.subscription.isActive)
                }
#if !targetEnvironment(macCatalyst) && !os(visionOS)
                Section {
                    if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .pad {
                        Label {
                            Toggle(isOn: $isCompact) {
                                Text("Compact Live Activities")
                            }
                            .tint(.accent)
                        } icon: {
                            Image(systemName: "widget.medium")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .bold()
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .foregroundStyle(Color.indigo)
                                )
                        }
                    }
                } footer: {
                    Text("Removes volumes controls and reduces size of Live Activities")
                }
#endif
                
#if !targetEnvironment(macCatalyst) && !os(visionOS)
                Section {
                    if UIDevice.current.userInterfaceIdiom == .phone {
//                        NavigationLink {
//                            Form {
//                                Toggle(isOn: $autoLaunchNowPlaying) {
//                                    Text("Auto launch to Group/Room playing on watch")
//                                    Text("Instantly jump to the group currently playing.")
//                                }
//                                .tint(.accent)
//                            }
//                        } label: {
                            Label {
                                Toggle(isOn: $autoLaunchNowPlaying) {
                                    Text("Auto Launch Watch")
                                }
                                .tint(.accent)
                            } icon: {
                                Image(systemName: "applewatch")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.white)
                                    .bold()
                                    .padding(8)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .foregroundStyle(.blue)
                                    )
                            }
                        
                        Label {
                            Toggle(isOn: $speedLaunchNowPlaying) {
                                Text("Auto Launch")
                            }
                            .tint(.accent)
                        } icon: {
                            Image(systemName: "iphone")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .bold()
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .foregroundStyle(.blue.gradient)
                                )
                        }
                    }

                } footer: {
                    Text("Launch to the group currently playing or in TV Mode.")
                }
#endif
                
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
                    Label {
                        HStack {
                            Link("Support hi@clic.dance", destination: URL(string: message)!)
                                .tint(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.up.forward")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "questionmark")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white)
                            .bold()
                            .padding(8)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .foregroundStyle(.yellow)
                            )
                    }
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
            .withAppRouter()
            .environment(\.defaultMinListHeaderHeight, 0)
            .addDismiss {
                dismiss()
            }
            .fontDesign(.rounded)
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .withAlert()
        .animation(.spring, value: alertService.alert.isShowing)
        .task {
            try? await subscriptionService.checkSubscription()
        }
        .onAppear {
            if OSEnvironment.isPreviews {
                sonosService.monitor()
            }
            
            if let destination {
                router.navigate(to: destination)
            }
            
#if targetEnvironment(macCatalyst)
            menuAppLaunchAtLoginManager.monitor()
#endif
        }
        .onDisappear {
#if targetEnvironment(macCatalyst)
            menuAppLaunchAtLoginManager.stopMonitor()
#endif
        }
        .customizeWindowSizeForMacOS15()
        .preferredColorScheme(colorScheme.scheme)
    }
    
    var colorSchemeSection: some View {
        Section {
            Label {
                Picker("Theme", selection: $colorScheme) {
                    ForEach(ColorSchemePreference.allCases, id: \.hashValue) { scheme in
                        Text(scheme.rawValue.capitalized)
                            .tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
            } icon: {
                Image(systemName: "circle.lefthalf.filled")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.foreground)
                    .bold()
                    .padding(8)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .foregroundStyle(.background)
                    )
            }
        } header: {
            Text("Appearance")
        }
    }
    
    var speedLaunch: some View {
        Section {
            Label {
                Picker("Theme", selection: $colorScheme) {
                    ForEach(ColorSchemePreference.allCases, id: \.hashValue) { scheme in
                        Text(scheme.rawValue.capitalized)
                            .tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
            } icon: {
                Image(systemName: "circle.lefthalf.filled")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.foreground)
                    .bold()
                    .padding(8)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .foregroundStyle(.background)
                    )
            }
        } header: {
            Text("Appearance")
        }
    }
}


#Preview {
    Text("Preference")
        .sheet(isPresented:.constant(true)) {
            PreferenceScreen()
                .withEnvironments()
        }
}
