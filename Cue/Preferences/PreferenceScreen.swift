import Analytics
import CloudStorage
import Defaults
import MusicSearchKit
import Nuke
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
    @Environment(FeatureGate.self) var featureGate
    
    var destination: RouterDestination? = nil
    
    @State private var router = Router()
    @State private var isShowingMailView = false
    @State private var refreshSonosLibrary = false
    @State private var libraryShare: String?
    
    @AppStorage("AppIcon") private var selectedAppIcon = "Default"
    
    @AppStorage("CueMiniEnabled") private var isMenuBarAppEnabled: Bool = true

    @AppStorage(Defaults.AppStorageKeys.colorScheme) private var colorScheme: ColorSchemePreference = .system
    @AppStorage(Defaults.AppStorageKeys.showRadioTab) private var showRadioTab: Bool = true
    @AppStorage(Defaults.AppStorageKeys.speedLaunchNowPlaying) private var speedLaunchNowPlaying: Bool = false
    @AppStorage(Defaults.AppStorageKeys.defaultPlayAction) private var replaceQueueByDefault: Bool = false
    @AppStorage(Defaults.AppStorageKeys.routeQueueTransfer) private var routeQueueTransfer: QueueTransferPreference = .ask
    @AppStorage(Defaults.AppStorageKeys.lastSeenWhatsNewVersion) private var lastSeenWhatsNewVersion: String = ""
    @AppStorage(Defaults.AppStorageKeys.latestReleaseVersion) private var latestReleaseVersion: String = ""
    @AppStorage(Defaults.AppStorageKeys.latestReleaseHeadline) private var latestReleaseHeadline: String = ""
    // Defaults to true, matching `UserDefaults.hardwareVolumeButtonsEnabled` —
    // see `AppStorageKeys.useHardwareVolumeButtons`. The switch has to show on
    // for someone who has never touched it, or the screen contradicts the
    // behaviour.
    @AppStorage(Defaults.AppStorageKeys.useHardwareVolumeButtons) private var useHardwareVolumeButtons: Bool = true

    private var hasUnseenWhatsNew: Bool {
        // Strict: the worker must have returned 200 for this bundle's
        // version. No data → no banner, even when forcing for debug.
        guard !latestReleaseVersion.isEmpty else { return false }
        if WhatsNewDebug.forceShowBanner { return true }
        return lastSeenWhatsNewVersion != latestReleaseVersion
    }

    @State private var presentWhatsNew = false
    
#if targetEnvironment(macCatalyst)
    @State private var menuAppLaunchAtLoginManager = MenuAppLaunchAtLoginManager.shared
    @State private var showCueMiniError = false
    @State private var cueMiniErrorMessage = ""
#endif
    
    @State private var isUploading = false
    @State private var uploadSuccess = false
    @State private var cacheSize: Int = 0
    @State private var isClearing = false
    @State private var libraryCacheSize: Int = 0
    @State private var offline = OfflineMode.shared

    
#if DEBUG
    @State private var servers: [MediaServer] = []
#endif
    
    var body: some View {
        @Bindable var sonosService = sonosService
        @Bindable var coreFeatures = coreFeatures
        
        NavigationStack(path: $router.path) {
            Form {
                if hasUnseenWhatsNew {
                    Section {
                        whatsNewBanner
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                    } header: {
                        Spacer(minLength: 0).listRowInsets(EdgeInsets())
                    }
                }

                Section {
                    if !subscriptionService.subscription.isActive {
                        PaywallButtonView()
                            .environment(router)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    } else {
                        Button {
                            HapticManager.shared.fireHaptic(.buttonPress)
                            Analytics.shared.track(.viewedPaywall)
                            router.presentedFullScreenCover = .paywall
                        } label: {
                            HStack(spacing: 12) {
                                Image("CueIconGlass")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("Cue Super")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(Color.accentColor.gradient)
                                    }
                                    subscriptionStatusLine
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
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
                    Label {
                        Toggle(isOn: sonosEnabledBinding) {
                            Text("Use Sonos Speakers")
                            Text("Find the Sonos speakers on your network and play on them")
                        }
                        .tint(.accent)
                    } icon: {
                        Image(systemName: "hifispeaker.2.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white)
                            .padding(7)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.25, blue: 0.3), Color(red: 0.1, green: 0.1, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    }

                    // Everything else here needs a speaker, so it only shows
                    // once speakers are switched on.
                    if sonosService.isEnabled {
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Households")
                                Text("Switch system")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Refresh Sonos Library")
                                if let share = libraryShare {
                                    Text(share)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
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


#if os(iOS) && !targetEnvironment(macCatalyst)
                    Label {
                        Toggle(isOn: $useHardwareVolumeButtons) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use iPhone Volume Buttons")
                                // Names the slider as well as the buttons —
                                // they're the same system volume, so the
                                // switch could never honour one and not the
                                // other. Names the exception too: it's a
                                // safety property, not a limitation. On
                                // Bluetooth or headphones that volume is the
                                // other device's.
                                Text("Volume buttons and the Lock Screen slider control the speaker instead of this device. Not while connected to Bluetooth or headphones.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.accent)
                    } icon: {
                        Image(systemName: "button.vertical.left.press.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white)
                            .bold()
                            .padding(8)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.5, blue: 0.3), Color(red: 0.85, green: 0.35, blue: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    }
                    // Super, like Lock Screen Now Playing it drives —
                    // `HardwareVolumeControlModifier` and the Lock Screen
                    // path both require it, so the row is editable in exactly
                    // the cases where it changes anything.
                    .gated(.hardwareVolumeButtons)
#endif
                    }
                } header: {
                    HStack {
                        Text("Sonos")
                            .foregroundStyle(.primary)
                        Spacer()
                        if sonosService.isEnabled {
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
                    }
                    .headerProminence(.increased)
                }
                Section {
                    NavigationLink(value: RouterDestination.servicePreferenceScreen) {
                        LabeledContent {
                            HStack {
                                ForEach(MediaSearchService.supported, id: \.self) { service in
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
                    // Scenes set up speakers — rooms, volumes, what plays.
                    if sonosService.isEnabled {
                    NavigationLink(value: RouterDestination.manageScenes) {
                        Label {
                            HStack {
                                Text("Scenes")
                                Spacer()
                                FeatureBadge(feature: .scenes)
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
                    }.gated(.scenes)
                    }
                } header: {
                    Text("Music")
                        .headerProminence(.increased)
                        .foregroundStyle(.primary)
                }
                Section {
                    Label {
                        Toggle(isOn: $replaceQueueByDefault) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Replace Queue by Default")
                                Text("Play Now replaces the queue instead of adding to it. Long-press for Play Next and Play Last options.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
                    // Same shape as the Lock Screen picker: three choices that
                    // exclude each other, so segments rather than toggles.
                    Label {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("When Switching Speakers")
                            Picker("When Switching Speakers", selection: $routeQueueTransfer) {
                                ForEach(QueueTransferPreference.allCases) { preference in
                                    Text(preference.title).tag(preference)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            Text(routeQueueTransfer.footnote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image("hifispeaker.arrow.forward.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white)
                            .bold()
                            .padding(7)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient(colors: [Color(red: 0.3, green: 0.8, blue: 0.55), Color(red: 0.1, green: 0.6, blue: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    }
                    // *Use iPhone Volume Buttons* used to sit here. It moved to
                    // the Lock Screen section, under the surface picker: it now
                    // gates that surface's slider as well as the buttons, and
                    // two volume controls in two sections — with a dependency
                    // between them that neither one showed — read as confusing.
                } header: {
                    Text("Playback")
                        .foregroundStyle(.primary)
                        .headerProminence(.increased)
                }
#if targetEnvironment(macCatalyst)
                // Cue Mini controls speakers and nothing else.
                if sonosService.isEnabled {
                Section {
                    // Open Cue Mini button
                    Button {
                        Task {
                            do {
                                try await menuAppLaunchAtLoginManager.bridge?.openCueMiniApp()
                            } catch {
                                cueMiniErrorMessage = error.localizedDescription
                                showCueMiniError = true
                            }
                        }
                    } label: {
                        Label {
                            HStack {
                                Text("Open Cue Mini")
                                Spacer()
                                Text("Open")
                                    .font(.subheadline.smallCaps())
                                    .foregroundStyle(.primary)
                                    .tint(.primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accent.gradient))
                            }
                        } icon: {
                            Image(systemName: "arrow.up.forward.app")
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
                    Label {
                        Toggle(isOn: $isMenuBarAppEnabled) {
                            Text("Launch with Cue")
                        }
                        .tint(.accent)
                        .onChange(of: isMenuBarAppEnabled) { _, newValue in
                            if newValue {
                                Task {
                                    do {
                                        try await menuAppLaunchAtLoginManager.bridge?.openCueMiniApp()
                                    } catch {
                                        cueMiniErrorMessage = error.localizedDescription
                                        showCueMiniError = true
                                    }
                                }
                            }
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
                } header: {
                    HStack {
                        Text("Cue Mini (Menu Bar)")
                            .foregroundStyle(.primary)
                        Spacer()
                        HStack(spacing: 5) {
                            Text(menuAppLaunchAtLoginManager.isRunning ? "Running" : "Not Running")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Circle()
                                .fill(menuAppLaunchAtLoginManager.isRunning ? .green : .red)
                                .frame(width: 6, height: 6)
                                .shadow(color: menuAppLaunchAtLoginManager.isRunning ? .green : .red, radius: 3, x: 0, y: 0)
                                .animation(.smooth, value: menuAppLaunchAtLoginManager.isRunning)
                        }
                    }
                    .headerProminence(.increased)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Control your Sonos directly from the menu bar without opening the full app.")
                        if !menuAppLaunchAtLoginManager.isRunning {
                            Link(destination: URL(string: "https://cue.dance/help#cuemini")!) {
                                HStack(spacing: 4) {
                                    Text("Having trouble?")
                                    Image(systemName: "arrow.up.forward")
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                }
                .alert("Unable to Open Cue Mini", isPresented: $showCueMiniError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(cueMiniErrorMessage)
                }
                }
                #endif
                colorSchemeSection
                storageCacheSection
                
#if !targetEnvironment(macCatalyst) && !os(visionOS)
                // Opens the player on whatever is playing — this device or a
                // speaker — so it's here with or without Sonos.
                Section {
                    Label {
                        Toggle(isOn: $speedLaunchNowPlaying) {
                            Text("iPhone & iPad")
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
                    Text("Quick Launch")
                        .foregroundStyle(.primary)
                        .headerProminence(.increased)
                } footer: {
                    Text("Opens Cue to Now Playing.")
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
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        router.presentedSheet = .newsletter
                    } label: {
                        Label {
                            HStack {
                                Text("Newsletter")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        } icon: {
                            Image(systemName: "envelope.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .bold()
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.62, blue: 0.70), Color(red: 0.10, green: 0.45, blue: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        }
                    }
                    .tint(.primary)

//                    NavigationLink(destination: ReleaseNotesView()) {
//                        Label {
//                            Text("Release Notes")
//                        } icon: {
//                            Image(systemName: "doc.text")
//                                .resizable()
//                                .aspectRatio(contentMode: .fit)
//                                .foregroundStyle(.white)
//                                .bold()
//                                .padding(8)
//                                .frame(width: 32, height: 32)
//                                .background(
//                                    RoundedRectangle(cornerRadius: 8)
//                                        .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.35, blue: 0.4), Color(red: 0.2, green: 0.2, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
//                                )
//                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
//                        }
//                    }
                    if !latestReleaseVersion.isEmpty {
                        NavigationLink(destination: WhatsNewWebView()) {
                            Label {
                                HStack {
                                    Text("What's New")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if hasUnseenWhatsNew {
                                        Circle()
                                            .fill(Color.accentColor)
                                            .frame(width: 8, height: 8)
                                    }
                                }
                            } icon: {
                                Image(systemName: "sparkles")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.white)
                                    .bold()
                                    .padding(8)
                                    .frame(width: 32, height: 32)
                                    .background {
                                        // Match the "NEW IN x.y" banner surface.
                                        // ZStack isn't a ShapeStyle, so use the
                                        // closure form + .clipShape.
                                        ZStack {
                                            Color(red: 10/255, green: 10/255, blue: 10/255)
                                            LinearGradient(
                                                stops: [
                                                    .init(color: Self.webTeal.opacity(0.55), location: 0.0),
                                                    .init(color: Color.clear, location: 0.45),
                                                    .init(color: Color.clear, location: 0.55),
                                                    .init(color: Self.webTeal.opacity(0.40), location: 1.0)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                            }
                        }
                    }
                    NavigationLink(destination: HelpWebView()) {
                        Label {
                            Text("Help & FAQ")
                        } icon: {
                            Image(systemName: "questionmark.circle")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .bold()
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [Color(red: 0.4, green: 0.7, blue: 0.95), Color(red: 0.25, green: 0.55, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        }
                    }
                    let message = "mailto:hi@cue.dance?subject=Support&body=\n\nVersion: \(OSEnvironment.versionInfo)\nID: \(subscriptionService.userID)"
                    Label {
                        HStack {
                            Link("Support hi@cue.dance", destination: URL(string: message)!)
                                .tint(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.up.forward")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "envelope")
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
                    Label {
                        HStack {
                            Link("Powered by Audioscrobbler", destination: URL(string: "https://www.last.fm")!)
                                .tint(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.up.forward")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "music.note.list")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white)
                            .bold()
                            .padding(8)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient(colors: [Color(red: 0.85, green: 0.15, blue: 0.15), Color(red: 0.65, green: 0.1, blue: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    }
                } header: {
                    Text("About")
                        .foregroundStyle(.primary)
                        .headerProminence(.increased)
                } footer: {
                    VStack(alignment: .center) {
                        Text("Version **\(OSEnvironment.versionInfo)**")
                        Text(subscriptionService.userID)
                            .textSelection(.enabled)
                            .scaledToFit()
                    }
                    .frame(maxWidth: .infinity)
                }

#if DEBUG
                Section("Debug") {
                    NavigationLink {
                        FeatureGateDebugView()
                            .withEnvironments()
                    } label: {
                        Label("Feature Gates", systemImage: "lock.open")
                    }
                }
#endif
            }
            .animation(.smooth(duration: 0.35), value: hasUnseenWhatsNew)
            .navigationTitle("Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $presentWhatsNew) {
                WhatsNewWebView()
            }
            .withAppRouter()
            .environment(\.defaultMinListHeaderHeight, 0)
            .addDismiss {
                dismiss()
            }
            .fontDesign(.rounded)
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
        .withAlert()
        .task {
            try? await subscriptionService.checkSubscription()
            libraryShare = await sonosService.libraryShare()
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
    }

    // Palette mirrors the website (--gradient-start: #5AADC4) so the in-app
    // banner reads as the same surface as the /latest page reels card.
    private static let webTeal = Color(red: 90/255, green: 173/255, blue: 196/255)
    private static let webTealAccent = Color(red: 124/255, green: 221/255, blue: 232/255) // #7CDDE8

    private struct WhatsNewBannerButtonStyle: ButtonStyle {
        func makeBody(configuration: ButtonStyleConfiguration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.7 : 1.0)
                .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
        }
    }

    @ViewBuilder
    private var whatsNewBanner: some View {
        Button {
            HapticManager.shared.fireHaptic(.buttonPress)
            presentWhatsNew = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NEW")
                        .font(.caption2.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(Self.webTealAccent)
                    Text(whatsNewHeadline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                // Website-style surface: mostly black with teal pulled in from
                // the leading and trailing edges. Holds up in both light and
                // dark mode since the base is solid.
                ZStack {
                    Color(red: 10/255, green: 10/255, blue: 10/255)
                    LinearGradient(
                        stops: [
                            .init(color: Self.webTeal.opacity(0.16), location: 0.0),
                            .init(color: Color.clear, location: 0.30),
                            .init(color: Color.clear, location: 0.70),
                            .init(color: Self.webTeal.opacity(0.10), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
        }
        .buttonStyle(WhatsNewBannerButtonStyle())
    }

    private var whatsNewHeadline: String {
        latestReleaseHeadline.isEmpty
            ? "See what's new in this update."
            : latestReleaseHeadline
    }

    private func presentPaywall() {
        featureGate.presentPaywall(via: router)
    }

    /// Turning speakers off moves playback back to this device first, so the
    /// route isn't left pointing at a group that is about to disappear. The
    /// speaker keeps playing its own queue; only Cue stops following it.
    private var sonosEnabledBinding: Binding<Bool> {
        Binding(
            get: { sonosService.isEnabled },
            set: { enabled in
                if !enabled, PlaybackRoute.shared.destination != .device {
                    PlaybackRoute.shared.switchTo(.device, carrying: false)
                }
                withAnimation {
                    sonosService.setEnabled(enabled)
                }
            }
        )
    }

    private var subscriptionStatusLine: Text {
        let info = subscriptionService.subscription.info
        let plan = info.flatMap { planName(for: $0.productIdentifier) }

        if plan == "Lifetime" {
            return Text("Lifetime")
        }
        if let info, let expiration = info.expirationDate {
            let dateText = Text(expiration, style: .date)
            let verb = info.willRenew ? "Renews" : "Expires"
            if let plan {
                return Text("\(plan) · \(verb) \(dateText)")
            }
            return Text("\(verb) \(dateText)")
        }
        if let plan {
            return Text(plan)
        }
        return Text("Active subscription")
    }

    private func planName(for productIdentifier: String) -> String? {
        let id = productIdentifier.lowercased()
        if id.contains("lifetime") { return "Lifetime" }
        if id.contains("annual") || id.contains("yearly") { return "Annual" }
        if id.contains("month") { return "Monthly" }
        return nil
    }

    var colorSchemeSection: some View {
        Section {
            Toggle(isOn: $showRadioTab) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Show Radio Tab")
                        Text("TuneIn and Apple Music stations in a tab of their own. Hidden on its own while offline.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "radio")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white)
                        .bold()
                        .padding(8)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.35, blue: 0.45), Color(red: 0.8, green: 0.2, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                }
            }
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
                .headerProminence(.increased)
        }
    }

    var storageCacheSection: some View {
        @Bindable var offline = offline
        return Section {
            Toggle(isOn: $offline.isOn) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Offline Mode")
                        Text(offline.hasNetwork
                             ? "Home shows only what's on this device, and everything plays here"
                             : "No network — on until the connection is back")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "airplane")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white)
                        .bold()
                        .padding(8)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.6, blue: 0.3), Color(red: 0.95, green: 0.45, blue: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                }
            }
            // With no network the app is offline whatever the switch says;
            // flipping it would promise a change that can't happen.
            .disabled(!offline.hasNetwork)

            NavigationLink(value: RouterDestination.downloads) {
                let downloads = DownloadManager.shared
                Label {
                    VStack(alignment: .leading) {
                        Text("Downloads")
                        Text(downloads.stoppedCount > 0
                             ? "\(downloads.stoppedCount) stopped • \(formattedSize(Int(downloads.completedBytes)))"
                             : downloads.hasActiveDownloads
                             ? "\(downloads.active.count) downloading • \(formattedSize(Int(downloads.completedBytes)))"
                             : formattedSize(Int(downloads.completedBytes)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white)
                        .bold()
                        .padding(8)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.6, blue: 1.0), Color(red: 0.2, green: 0.45, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                }
            }

            if WatchSyncService.shared.isPaired {
                NavigationLink {
                    WatchSettingsScreen()
                } label: {
                    let watch = WatchSyncService.shared
                    Label {
                        VStack(alignment: .leading) {
                            Text("Apple Watch")
                            Text(!watch.isWatchAppInstalled
                                 ? "Install Cue on your watch to take music with you"
                                 : watch.picks.items.isEmpty
                                 ? "Take Plex and Subsonic music with you"
                                 : watch.picks.items.count == 1 ? "1 item" : "\(watch.picks.items.count) items")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "applewatch")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white)
                            .bold()
                            .padding(7)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient(colors: [Color(red: 0.4, green: 0.4, blue: 0.45), Color(red: 0.2, green: 0.2, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    }
                }
            }

            Button {
                Task {
                    isClearing = true
                    await clearImageCache()
                    isClearing = false
                }
            } label: {
                Label {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Clear Image Cache")
                            Text(formattedCacheSize)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isClearing {
                            ProgressView()
                        }
                    }
                } icon: {
                    Image(systemName: "trash")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white)
                        .bold()
                        .padding(8)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.4, blue: 0.4), Color(red: 0.85, green: 0.25, blue: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                }
            }
            .tint(.primary)
            .disabled(isClearing || cacheSize == 0)

            // Only for people who have a self-hosted library to cache.
            if libraryCacheSize > 0 {
                Button {
                    clearLibraryCache()
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Clear Library Cache")
                            Text(formattedSize(libraryCacheSize))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "externaldrive.fill.badge.xmark")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white)
                            .bold()
                            .padding(8)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.4, blue: 0.4), Color(red: 0.85, green: 0.25, blue: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    }
                }
                .tint(.primary)
            }
        } header: {
            Text("Storage")
                .foregroundStyle(.primary)
                .headerProminence(.increased)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Clears cached artwork images. Images will be re-downloaded as needed.")
                if libraryCacheSize > 0 {
                    Text("The library cache is the copy of your music libraries that Songs is sorted and searched from. It re-syncs the next time you open Songs.")
                }
            }
        }
        .task {
            await updateCacheSize()
            libraryCacheSize = SubsonicAPI.shared.cachedSongLibrarySize
                + PlexAPI.shared.cachedSongLibrarySize
                + LibraryBrowseService.cachedSongLibrarySize
        }
    }

    private func clearLibraryCache() {
        HapticManager.shared.fireHaptic(.buttonPress)
        // Drops the in-memory copy and the file together, so the next visit
        // really does re-read the server.
        musicSearchService.clearSubsonicSongCache()
        musicSearchService.clearPlexSongCache()
        LibraryBrowseService.shared.clearSongCache()
        libraryCacheSize = 0
        alertService.showAlert(with: "Cache Cleared", imageName: "trash")
    }

    private var formattedCacheSize: String { formattedSize(cacheSize) }

    private func formattedSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func updateCacheSize() async {
        if let dataCache = try? DataCache(name: "com.cue.imageCache") {
            cacheSize = dataCache.totalSize
        }
    }

    private func clearImageCache() async {
        HapticManager.shared.fireHaptic(.buttonPress)

        // Clear memory cache
        ImageCache.shared.removeAll()

        // Clear disk cache
        if let dataCache = try? DataCache(name: "com.cue.imageCache") {
            dataCache.removeAll()
            dataCache.flush()
        }

        // Reset to zero immediately since we just cleared
        cacheSize = 0

        HapticManager.shared.fireHaptic(.buttonPress)
        alertService.showAlert(with: "Cache Cleared", imageName: "trash")
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
        request.addValue("Bearer cue6043", forHTTPHeaderField: "Authorization")
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

/// The capsule that marks a Cue Super feature in Preferences.
struct SuperBadge: View {
    var body: some View {
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
}

#Preview {
    Text("Preference")
        .sheet(isPresented: .constant(true)) {
            PreferenceScreen()
                .withEnvironments()
        }
}
