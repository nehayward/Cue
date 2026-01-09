import Analytics
import CloudStorage
import Defaults
import MusicSearchKit
import RevenueCat
import RevenueCatUI
import SonosKit
import SubscriptionKit
import SwiftUI

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
    @AppStorage("LiveActivityStep", store: UserDefaults(suiteName: "group.com.clic")) private var liveActivityStep: Int = 5
    
    @AppStorage("ClicMiniEnabled") private var isMenuBarAppEnabled: Bool = true
    
    @AppStorage(Defaults.AppStorageKeys.colorScheme) private var colorScheme: ColorSchemePreference = .system
    @AppStorage(Defaults.AppStorageKeys.speedLaunchNowPlaying) private var speedLaunchNowPlaying: Bool = false
    @AppStorage(Defaults.AppStorageKeys.defaultPlayAction) private var replaceQueueByDefault: Bool = false
    @CloudStorage("com.clic.autoLaunchNowPlaying") private var autoLaunchNowPlaying: Bool = true
    
#if targetEnvironment(macCatalyst)
    @State private var menuAppLaunchAtLoginManager = MenuAppLaunchAtLoginManager.shared
    @State private var showClicMiniError = false
    @State private var clicMiniErrorMessage = ""
#endif
    
    @State private var isUploading = false
    @State private var uploadSuccess = false
    
#if DEBUG
    @State private var servers: [MediaServer] = []
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
                        Button {
                            HapticManager.shared.fireHaptic(.buttonPress)
                            showManageSubscriptions = true
                            Analytics.shared.track(.viewedManageSubscription)
                        } label: {
                            HStack(spacing: 12) {
                                Image("clic.icon")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.white)
                                    .padding(8)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.accentColor.gradient)
                                    )
                                    .shadow(color: Color.accentColor.opacity(0.4), radius: 4, x: 0, y: 2)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("Clic Super")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(Color.accentColor.gradient)
                                    }
                                    if let info = subscriptionService.subscription.info, let expiration = info.expirationDate {
                                        if info.willRenew {
                                            Text("Renews \(Text(expiration, style: .date))")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("Expires \(Text(expiration, style: .date))")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    } else {
                                        Text("Active subscription")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.primary)
                    }
                } header: {
                    Spacer(minLength: 0).listRowInsets(EdgeInsets())
                }
                
                //#if DEBUG
                //                Section("Discovered") {
                //                    ForEach(servers) { server in
                //                        VStack(alignment: .leading) {
                //                            HStack {
                //                                Text(server.name).bold()
                //                                Text(server.type.rawValue)
                //                            }
                //                            Text("\(server.token)")
                //                                .textSelection(.enabled)
                //                                .lineLimit(1)
                //                        }
                //                    }
                //                }
                //#endif
                
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
                    NavigationLink(value: RouterDestination.connectByIP) {
                        Label {
                            Text("Connectivity")
                        } icon: {
                            Image(systemName: "network")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.55, blue: 0.6), Color(red: 0.4, green: 0.4, blue: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        }
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
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.25, blue: 0.3), Color(red: 0.1, green: 0.1, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
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
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.7, blue: 0.3), Color(red: 0.95, green: 0.5, blue: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        }
                    }

                    NavigationLink(value: RouterDestination.houseHold) {
                        Label {
                            Text("Switch Households")
                        } icon: {
                            Image("home.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [Color(red: 0.4, green: 0.6, blue: 0.95), Color(red: 0.25, green: 0.45, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
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
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [Color(red: 0.3, green: 0.85, blue: 0.6), Color(red: 0.2, green: 0.7, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        }
                    }
                    .tint(.primary)
                } header: {
                    HStack {
                        Text("Sonos")
                            .foregroundStyle(.primary)
                        Spacer()
                        HStack(spacing: 5) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(!sonosService.sonosPulse.isCancelled ? .green : .red)
                                .shadow(color: !sonosService.sonosPulse.isCancelled ? .green : .red, radius: 3, x: 0, y: 0)
                            Text(!sonosService.sonosPulse.isCancelled ? "Connected" : "Offline")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .headerProminence(.increased)
                }
                Section {
                    NavigationLink(value: RouterDestination.servicePreferenceScreen) {
                        LabeledContent {
                            HStack {
                                ForEach(MediaSearchService.allCases, id: \.self) { service in
                                    if coreFeatures.enabledServices(service).wrappedValue {
                                        service.iconForMusicService
                                            .frame(width: 16, height: 16)
                                    }
                                }
                            }
                        } label: {
                            Label {
                                Text("Services")
                            } icon: {
                                Image(systemName: "music.note")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.white)
                                    .bold()
                                    .padding(8)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.3, blue: 0.5), Color(red: 0.85, green: 0.2, blue: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    )
                                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                            }
                        }
                    }
                    NavigationLink(value: RouterDestination.manageScenes) {
                        Label {
                            HStack {
                                Text("Scenes")
                                Spacer()
                                Text("Super")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .textCase(.uppercase)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.accentColor.gradient)
                                    )
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
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [Color(red: 0.3, green: 0.85, blue: 0.85), Color(red: 0.2, green: 0.7, blue: 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        }
                    }.disabled(!subscriptionService.subscription.isActive)
                } header: {
                    Text("Music")
                        .headerProminence(.increased)
                        .foregroundStyle(.primary)
                }
                Section {
                    Label {
                        Toggle(isOn: $replaceQueueByDefault) {
                            Text("Replace Queue by Default")
                        }
                        .tint(.accent)
                    } icon: {
                        Image(systemName: "play.square.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white)
                            .bold()
                            .padding(8)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient(colors: [Color(red: 0.7, green: 0.5, blue: 0.95), Color(red: 0.55, green: 0.35, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    }
                } header: {
                    Text("Playback")
                        .foregroundStyle(.primary)
                        .headerProminence(.increased)
                } footer: {
                    Text( "When enabled, tapping a song or album will replace the current queue instead of adding it next. You can still use long-press to access 'Play Next' and 'Play Last' options.")
                }
#if targetEnvironment(macCatalyst)
                Section {
                    // Status indicator
                    HStack {
                        Label {
                            HStack {
                                Text("Status")
                                Spacer()
                                HStack(spacing: 6) {
                                    Image(systemName: "circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(menuAppLaunchAtLoginManager.isRunning ? .green : .red)
                                        .shadow(color: menuAppLaunchAtLoginManager.isRunning ? .green : .red, radius: 2, x: 0, y: 0)
                                    Text(menuAppLaunchAtLoginManager.isRunning ? "Running" : "Not Running")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .animation(.spring, value: menuAppLaunchAtLoginManager.isRunning)
                        } icon: {
                            Image(systemName: "info.circle.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .bold()
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [Color(red: 0.4, green: 0.65, blue: 0.95), Color(red: 0.25, green: 0.5, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        }
                    }

                    // Open Clic Mini button
                    Button {
                        Task {
                            do {
                                try await menuAppLaunchAtLoginManager.macUtils?.openClicMiniApp()
                            } catch {
                                clicMiniErrorMessage = error.localizedDescription
                                showClicMiniError = true
                            }
                        }
                    } label: {
                        Label {
                            HStack {
                                Text("Open Clic Mini")
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("Launch")
                                        .font(.subheadline.smallCaps())
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .foregroundStyle(.accent)
                                        )
                                }
                            }
                        } icon: {
                            Image(systemName: "arrow.up.forward.circle.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .bold()
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.85, blue: 0.55), Color(red: 0.25, green: 0.7, blue: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        }
                    }
                    .tint(.primary)

                    // Auto-launch toggle
                    Button {
                        isMenuBarAppEnabled.toggle()
                        if isMenuBarAppEnabled {
                            Task {
                                do {
                                    try await menuAppLaunchAtLoginManager.macUtils?.openClicMiniApp()
                                } catch {
                                    clicMiniErrorMessage = error.localizedDescription
                                    showClicMiniError = true
                                }
                            }
                        }
                    } label: {
                        Label {
                            HStack {
                                Text("Auto-Launch with Clic")
                                Spacer()
                                Toggle(isOn: $isMenuBarAppEnabled) {
                                    Text("Enable Clic Mini")
                                }
                                .tint(.accent)
                                .labelsHidden()
                                .allowsHitTesting(false)
                            }
                        } icon: {
                            Image(systemName: "play.circle.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .bold()
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [Color(red: 0.4, green: 0.85, blue: 0.95), Color(red: 0.25, green: 0.7, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        }
                    }
                    .tint(.primary)
                } header: {
                    Label("Clic Mini (Menu Bar App)", systemImage: "menubar.rectangle")
                        .foregroundStyle(.primary)
                } footer: {
                    Text("Clic Mini provides quick access to playback controls from your menu bar. Enable auto-launch to have it start automatically when you open Clic.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .alert("Unable to Open Clic Mini", isPresented: $showClicMiniError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(clicMiniErrorMessage)
                }
                #endif
                colorSchemeSection
#if !targetEnvironment(macCatalyst) && !os(visionOS)
                Section {
                    if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .pad {
                        if #available(iOS 26.0, *) {
                            VStack(alignment: .leading) {
                                Text("⚠️ iOS 26 Limitation")
                                    .fontWeight(.bold)
                                Text("Due to an iOS 26 system bug, the number of buttons in a Live Activity is currently limited. The volume step and mute button controls have been temporarily removed. We hope this will be resolved in a later update to iOS 26.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Label {
                            Toggle(isOn: $isCompact) {
                                Text("Compact Live Activities")
                                Text("Removes volumes controls and reduces size of Live Activities")
                            }
                            .tint(.accent)
                        } icon: {
                            Image(systemName: "inset.filled.capsule")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .bold()
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.45, blue: 0.95), Color(red: 0.4, green: 0.3, blue: 0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        }

                        Label {
                            Stepper(value: $liveActivityStep, in: 1...10) {
                                Text("Volume Steps: ") +  Text(liveActivityStep, format: .number).bold()
                                Text("Adjust how much the volume changes with each step in Live Activities.")
                            }
                            .sensoryFeedback(.levelChange, trigger: liveActivityStep)
                        } icon: {
                            Image(systemName: "plus.minus.capsule")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .bold()
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [Color(red: 0.6, green: 0.5, blue: 0.98), Color(red: 0.45, green: 0.35, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        }
                    }
                } header: {
                    Text("Live Activities")
                        .foregroundStyle(.primary)
                        .headerProminence(.increased)

                }
#endif
                
#if !targetEnvironment(macCatalyst) && !os(visionOS)
                Section {
                    if UIDevice.current.userInterfaceIdiom == .phone {
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
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [Color(red: 0.4, green: 0.65, blue: 0.95), Color(red: 0.25, green: 0.5, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        }
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
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.6, blue: 0.95), Color(red: 0.2, green: 0.45, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    }
                } header: {
                    Text("Launch")
                        .foregroundStyle(.primary)
                        .headerProminence(.increased)
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
                //                                print("Failed request to update the app's icon: \(error)")
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
                    NavigationLink(destination: ReleaseNotesView()) {
                        Label {
                            Text("Release Notes")
                        } icon: {
                            Image(systemName: "doc.text")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .bold()
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.35, blue: 0.4), Color(red: 0.2, green: 0.2, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        }
                    }
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
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.45, blue: 0.45), Color(red: 0.85, green: 0.3, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    }
                } header: {
                    Text("About")
                        .foregroundStyle(.primary)
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
        .task {
            try? await subscriptionService.checkSubscription()
#if DEBUG
            servers = await sonosService.services()
#endif
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
        .presentationSizingiOS18()
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
                    .foregroundStyle(.white)
                    .bold()
                    .padding(8)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.55, blue: 0.6), Color(red: 0.4, green: 0.4, blue: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            }
        } header: {
            Text("Appearance")
                .foregroundStyle(.primary)
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
                    .foregroundStyle(.white)
                    .bold()
                    .padding(8)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.55, blue: 0.6), Color(red: 0.4, green: 0.4, blue: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            }
        } header: {
            Text("Appearance")
                .foregroundStyle(.primary)
        }
    }
    
    private func uploadLogs(text: String) async {
        if text.isEmpty { return }
        // Define the URL and request
        guard let id =  UIDevice.current.identifierForVendor?.uuidString else { return }
        guard let url = URL(string: "https://tight-night-3b05.nehayward.workers.dev/\(Date.now.ISO8601Format(.iso8601Date(timeZone: .current, dateSeparator: .omitted)))_\(id).txt") else {
            fatalError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("Bearer clic6043", forHTTPHeaderField: "Authorization")
        request.httpBody = text.data(using: .utf8)

        // Perform the async URLSession call
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("Status Code: \(httpResponse.statusCode)")
            }

            // Handle the response data
            if let responseData = String(data: data, encoding: .utf8) {
                print("Response Data: \(responseData)")
            }
        } catch {
            print("Request failed with error: \(error)")
        }
    }
}

#Preview {
    Text("Preference")
        .sheet(isPresented: .constant(true)) {
            PreferenceScreen()
                .withEnvironments()
        }
}
