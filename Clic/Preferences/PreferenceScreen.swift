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
    
    var destination: RouterDestination? = nil
    
    @State private var router = Router()
    @State private var isShowingMailView = false
    @State private var refreshSonosLibrary = false
    @State private var libraryShare: String?
    
    @AppStorage("AppIcon") private var selectedAppIcon = "Default"
    @AppStorage("isCompact", store: UserDefaults(suiteName: "group.com.clic")) private var isCompact: Bool = false
    @AppStorage("LiveActivityStep", store: UserDefaults(suiteName: "group.com.clic")) private var liveActivityStep: Int = 5
    
    @AppStorage("ClicMiniEnabled") private var isMenuBarAppEnabled: Bool = true

    @AppStorage(Defaults.AppStorageKeys.colorScheme) private var colorScheme: ColorSchemePreference = .system
    @AppStorage(Defaults.AppStorageKeys.speedLaunchNowPlaying) private var speedLaunchNowPlaying: Bool = false
    @AppStorage(Defaults.AppStorageKeys.defaultPlayAction) private var replaceQueueByDefault: Bool = false
    @AppStorage(Defaults.AppStorageKeys.lastSeenWhatsNewVersion) private var lastSeenWhatsNewVersion: String = ""
    @AppStorage(Defaults.AppStorageKeys.latestReleaseVersion) private var latestReleaseVersion: String = ""
    @AppStorage(Defaults.AppStorageKeys.latestReleaseHeadline) private var latestReleaseHeadline: String = ""
    @AppStorage(Defaults.AppStorageKeys.useHardwareVolumeButtons) private var useHardwareVolumeButtons: Bool = false
    // Defaults to true: Now Playing is the default Lock Screen surface for Clic
    // Super. `NowPlayingSessionService.isEnabled` still requires the
    // subscription, so this being on doesn't start anything on its own.
    @AppStorage(Defaults.AppStorageKeys.lockScreenNowPlaying) private var lockScreenNowPlaying: Bool = true
    // Defaults to true: this switch arrived after Live Activities shipped, so an
    // absent value has to mean the behaviour every existing install already has.
    // Shared suite — the widget intents start activities from another process.
    @AppStorage(Defaults.GroupStorageKeys.liveActivities, store: Defaults.GroupStorageKeys.storage)
    private var liveActivities: Bool = true
    @AppStorage(Defaults.GroupStorageKeys.liveActivitiesSuspendedByLockScreen, store: Defaults.GroupStorageKeys.storage)
    private var liveActivitiesSuspendedByLockScreen: Bool = false

    private var hasUnseenWhatsNew: Bool {
        // Strict: the worker must have returned 200 for this bundle's
        // version. No data → no banner, even when forcing for debug.
        guard !latestReleaseVersion.isEmpty else { return false }
        if WhatsNewDebug.forceShowBanner { return true }
        return lastSeenWhatsNewVersion != latestReleaseVersion
    }

    @State private var presentWhatsNew = false
    @CloudStorage("com.clic.autoLaunchNowPlaying") private var autoLaunchNowPlaying: Bool = true
    
#if targetEnvironment(macCatalyst)
    @State private var menuAppLaunchAtLoginManager = MenuAppLaunchAtLoginManager.shared
    @State private var showClicMiniError = false
    @State private var clicMiniErrorMessage = ""
#endif
    
    @State private var isUploading = false
    @State private var uploadSuccess = false
    @State private var cacheSize: Int = 0
    @State private var isClearing = false

    
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
                                Image("ClicIconGlass")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("Clic Super")
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

                    Button {
                        router.sheet(to: .shareToWatch)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Share to Watch")
                                Text("Connect Watch without network discovery")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "qrcode")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.white)
                                .bold()
                                .padding(8)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.6, blue: 0.2), Color(red: 0.95, green: 0.4, blue: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
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
                                // Only while it's still something to buy — once
                                // subscribed the badge is noise on every Super row.
                                if !subscriptionService.subscription.isActive {
                                    SuperBadge()
                                }
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
#if os(iOS) && !targetEnvironment(macCatalyst)
                    Label {
                        Toggle(isOn: $useHardwareVolumeButtons) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use iPhone Volume Buttons")
                                // Names the Lock Screen because this switch now
                                // gates that surface's volume slider too — same
                                // system volume, so there is no honouring it in
                                // one place and not the other. Names the
                                // exception because it's a safety property, not
                                // a limitation: on Bluetooth or headphones the
                                // volume is the other device's.
                                Text("Control group volume instead of iPhone volume, including from the Lock Screen. Never while connected to Bluetooth or headphones.")
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
#endif
                } header: {
                    Text("Playback")
                        .foregroundStyle(.primary)
                        .headerProminence(.increased)
                }
#if !targetEnvironment(macCatalyst) && !os(visionOS)
                Section {
#if os(iOS) && !targetEnvironment(macCatalyst)
                    // The choice the rest of this section sits under, so it goes
                    // first. One control rather than two toggles: the surfaces
                    // are mutually exclusive, and a pair of switches that
                    // silently move each other reads as a bug — a picker says
                    // "pick one" on its face.
                    Label {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text("Lock Screen")
                                if !subscriptionService.subscription.isActive {
                                    SuperBadge()
                                }
                            }
                            Picker("Lock Screen", selection: lockScreenSurfaceBinding) {
                                ForEach(LockScreenSurface.allCases) { surface in
                                    Text(surface.title).tag(surface)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            Text(lockScreenSurface.footnote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "lock.iphone")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white)
                            .bold()
                            .padding(8)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.65, blue: 0.95), Color(red: 0.2, green: 0.45, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    }
                    // Greyed out without Super, the same way the Scenes row is.
                    // Every option here needs a subscription — `ClicApp` won't
                    // even start a Live Activity without one — so there is
                    // nothing to leave enabled.
                    .disabled(!subscriptionService.subscription.isActive)
                    // Outside the `.disabled`, so it still takes taps: a
                    // disabled row can't open the paywall by itself.
                    .overlay {
                        if !subscriptionService.subscription.isActive {
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onTapGesture(perform: presentPaywall)
                        }
                    }
#endif
                    if UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .pad {
                        // Both of these only shape the Live Activity, so they're
                        // dimmed rather than hidden when it isn't the chosen
                        // surface — the picker directly above says why, and the
                        // section doesn't resize as you move between segments.
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
                        .disabled(!subscriptionService.subscription.isActive || lockScreenSurface != .liveActivity)

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
                        .disabled(!subscriptionService.subscription.isActive || lockScreenSurface != .liveActivity)
                    }
                } header: {
                    Text("Lock Screen")
                        .foregroundStyle(.primary)
                        .headerProminence(.increased)

                }
#endif
#if targetEnvironment(macCatalyst)
                Section {
                    // Open Clic Mini button
                    Button {
                        Task {
                            do {
                                try await menuAppLaunchAtLoginManager.bridge?.openClicMiniApp()
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
                            Text("Launch with Clic")
                        }
                        .tint(.accent)
                        .onChange(of: isMenuBarAppEnabled) { _, newValue in
                            if newValue {
                                Task {
                                    do {
                                        try await menuAppLaunchAtLoginManager.bridge?.openClicMiniApp()
                                    } catch {
                                        clicMiniErrorMessage = error.localizedDescription
                                        showClicMiniError = true
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
                        Text("Clic Mini (Menu Bar)")
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
                            Link(destination: URL(string: "https://clic.dance/help#clicmini")!) {
                                HStack(spacing: 4) {
                                    Text("Having trouble?")
                                    Image(systemName: "arrow.up.forward")
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                }
                .alert("Unable to Open Clic Mini", isPresented: $showClicMiniError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(clicMiniErrorMessage)
                }
                #endif
                colorSchemeSection
                storageCacheSection
                
#if !targetEnvironment(macCatalyst) && !os(visionOS)
                Section {
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        Label {
                            Toggle(isOn: $autoLaunchNowPlaying) {
                                Text("Apple Watch")
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
                    Text("Opens to Now Playing instead of the room list.")
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
                        Text(Purchases.shared.appUserID)
                            .textSelection(.enabled)
                            .scaledToFit()
                    }
                    .frame(maxWidth: .infinity)
                }
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
        .preferredColorScheme(colorScheme.scheme)
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

    /// What the Lock Screen shows while a speaker is playing. The three states
    /// are exclusive by construction — one picker instead of two switches that
    /// silently moved each other, which is what the pair looked like from the
    /// outside.
    private enum LockScreenSurface: String, CaseIterable, Identifiable {
        /// A Clic card, per playing speaker. What everyone gets without Super.
        case liveActivity
        /// The system Now Playing card, driven by the silent audio session. The
        /// default with Clic Super — the preference is on unless turned off.
        case nowPlaying
        case off

        var id: String { rawValue }

        var title: String {
            switch self {
            case .liveActivity: return "Live Activity"
            case .nowPlaying: return "Now Playing"
            case .off: return "Off"
            }
        }

        var footnote: String {
            switch self {
            case .liveActivity:
                return "A Clic card on the Lock Screen and Dynamic Island for each playing speaker."
            case .nowPlaying:
                // No promises about a volume slider: what the system player
                // draws is the system's call and differs by device — an iPad
                // reported artwork and buttons but no slider.
                //
                // Volume is named separately from audio because it's a separate
                // opt-in now: the bridge runs only with *Use iPhone Volume
                // Buttons* on, and never while this device's audio is on
                // Bluetooth, CarPlay or headphones. It used to run
                // unconditionally, which is how a car-connect automation set a
                // Sonos group to 100%.
                return "The system player on the Lock Screen and in Control Center. Clic takes over this device's audio while a speaker is playing."
            case .off:
                return "Nothing on the Lock Screen while a speaker is playing."
            }
        }
    }

    private func presentPaywall() {
        HapticManager.shared.fireHaptic(.buttonPress)
        Analytics.shared.track(.viewedPaywall)
        router.presentedFullScreenCover = .paywall
    }

    /// Derived, never stored: two booleans already describe this, and a third
    /// copy would be one more thing to keep in step.
    ///
    /// No subscription check here, deliberately. Nothing in this section runs
    /// without Super — `ClicApp` won't start a Live Activity either — so the
    /// whole row is disabled rather than partly usable, and what it shows while
    /// greyed is an honest preview of what a subscriber would get.
    private var lockScreenSurface: LockScreenSurface {
        if lockScreenNowPlaying { return .nowPlaying }
        return liveActivities ? .liveActivity : .off
    }

    /// Now Playing is Clic Super. Selecting it without a subscription presents
    /// the paywall and writes nothing, so the picker snaps back on its own and
    /// `NowPlayingSessionService` never sees a value it would have to undo.
    /// Moving *away* from it always goes through, so a lapsed subscriber isn't
    /// stuck on a setting they can't change.
    private var lockScreenSurfaceBinding: Binding<LockScreenSurface> {
        Binding(
            get: { lockScreenSurface },
            set: { surface in
                switch surface {
                case .nowPlaying:
                    guard subscriptionService.subscription.isActive else {
                        presentPaywall()
                        return
                    }
                    // Only this one write. `NowPlayingSessionService.reconcile-
                    // LiveActivities()` turns Live Activities off and records
                    // that it was the cause, so moving back restores them —
                    // duplicating that here would give the invariant two owners.
                    lockScreenNowPlaying = true
                case .liveActivity:
                    // Clear Lock Screen Controls *first*: the defaults change
                    // each write posts is what wakes the service, and it would
                    // otherwise read "still on" and turn these straight back off.
                    lockScreenNowPlaying = false
                    liveActivitiesSuspendedByLockScreen = false
                    liveActivities = true
                case .off:
                    lockScreenNowPlaying = false
                    liveActivitiesSuspendedByLockScreen = false
                    liveActivities = false
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
        Section {
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
        } header: {
            Text("Storage")
                .foregroundStyle(.primary)
                .headerProminence(.increased)
        } footer: {
            Text("Clears cached artwork images. Images will be re-downloaded as needed.")
        }
        .task {
            await updateCacheSize()
        }
    }

    private var formattedCacheSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(cacheSize))
    }

    private func updateCacheSize() async {
        if let dataCache = try? DataCache(name: "com.clic.imageCache") {
            cacheSize = dataCache.totalSize
        }
    }

    private func clearImageCache() async {
        HapticManager.shared.fireHaptic(.buttonPress)

        // Clear memory cache
        ImageCache.shared.removeAll()

        // Clear disk cache
        if let dataCache = try? DataCache(name: "com.clic.imageCache") {
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

/// The capsule that marks a Clic Super feature in Preferences.
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
