import Defaults
import SonosKit
import SwiftUI

/// Settings ▸ Sonos: the switch that turns speakers on, then everything that
/// needs one — connecting, the speakers' own settings, alarms, households,
/// the library, the iPhone's volume buttons, scenes and, on the Mac, Cue
/// Mini. A page of its own, so Preferences stays a short list of places
/// and someone without speakers never scrolls past them.
struct SonosSettingsScreen: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(AlertService.self) private var alertService

    @State private var libraryShare: String?

#if os(iOS) && !targetEnvironment(macCatalyst)
    // Defaults to true, matching `UserDefaults.hardwareVolumeButtonsEnabled` —
    // see `AppStorageKeys.useHardwareVolumeButtons`. The switch has to show on
    // for someone who has never touched it, or the screen contradicts the
    // behaviour.
    @AppStorage(AppStorageKeys.useHardwareVolumeButtons) private var useHardwareVolumeButtons: Bool = true
#endif

#if targetEnvironment(macCatalyst)
    @AppStorage("CueMiniEnabled") private var isMenuBarAppEnabled: Bool = true
    @State private var menuAppLaunchAtLoginManager = MenuAppLaunchAtLoginManager.shared
    @State private var showCueMiniError = false
    @State private var cueMiniErrorMessage = ""
#endif

    var body: some View {
        Form {
            Section {
                Label {
                    Toggle(isOn: sonosEnabledBinding) {
                        SettingsRowText(title: "Use Sonos Speakers", detail: "Find the Sonos speakers on your network and play on them")
                    }
                    .tint(.accent)
                } icon: {
                    SettingsIcon(symbol: "hifispeaker.fill", colors: [Color(red: 0.25, green: 0.25, blue: 0.3), Color(red: 0.1, green: 0.1, blue: 0.15)])
                }
            } footer: {
                if sonosService.isEnabled {
                    HStack(spacing: 5) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(isConnected ? .green : .red)
                        Text(isConnected ? "Connected" : "Offline")
                    }
                }
            }

            // Everything else here needs a speaker, so it only shows once
            // speakers are switched on.
            if sonosService.isEnabled {
                speakersSection
#if os(iOS) && !targetEnvironment(macCatalyst)
                volumeButtonsSection
#endif
#if targetEnvironment(macCatalyst)
                cueMiniSection
#endif
            }
        }
        .navigationTitle("Sonos")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .animation(.default, value: sonosService.isEnabled)
        .task {
            libraryShare = await sonosService.libraryShare()
        }
#if targetEnvironment(macCatalyst)
        .onAppear { menuAppLaunchAtLoginManager.monitor() }
        .onDisappear { menuAppLaunchAtLoginManager.stopMonitor() }
#endif
    }

    private var isConnected: Bool { !sonosService.sonosPulse.isCancelled }

    private var speakersSection: some View {
        Section {
            NavigationLink(value: RouterDestination.connectByIP) {
                Label {
                    Text("Connectivity")
                } icon: {
                    SettingsIcon(symbol: "network", colors: [Color(red: 0.55, green: 0.55, blue: 0.6), Color(red: 0.4, green: 0.4, blue: 0.45)])
                }
            }

            NavigationLink(value: RouterDestination.speakerSettingsList) {
                Label {
                    Text("Speaker Settings")
                } icon: {
                    SettingsIcon(symbol: "slider.horizontal.3", colors: [Color(red: 0.55, green: 0.55, blue: 0.6), Color(red: 0.4, green: 0.4, blue: 0.45)])
                }
            }

            NavigationLink(value: RouterDestination.alarms) {
                Label {
                    Text("Alarms")
                } icon: {
                    SettingsIcon(symbol: "alarm.fill", colors: [Color(red: 1.0, green: 0.7, blue: 0.3), Color(red: 0.95, green: 0.5, blue: 0.2)])
                }
            }

            NavigationLink(value: RouterDestination.manageScenes) {
                Label {
                    HStack {
                        Text("Scenes")
                        Spacer()
                        FeatureBadge(feature: .scenes)
                    }
                } icon: {
                    SettingsIcon(symbol: "bolt.fill", colors: [Color(red: 0.3, green: 0.85, blue: 0.85), Color(red: 0.2, green: 0.7, blue: 0.7)])
                }
            }
            .gated(.scenes)

            NavigationLink(value: RouterDestination.houseHold) {
                Label {
                    SettingsRowText(title: "Households", detail: "Switch system")
                } icon: {
                    SettingsIcon(symbol: "home.fill", isAsset: true, colors: [Color(red: 0.4, green: 0.6, blue: 0.95), Color(red: 0.25, green: 0.45, blue: 0.85)])
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
                        if let libraryShare {
                            Text(libraryShare)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                } icon: {
                    SettingsIcon(symbol: "arrow.clockwise", colors: [Color(red: 0.3, green: 0.85, blue: 0.6), Color(red: 0.2, green: 0.7, blue: 0.5)])
                }
            }
            .tint(.primary)
        }
    }

#if os(iOS) && !targetEnvironment(macCatalyst)
    private var volumeButtonsSection: some View {
        Section {
            Label {
                Toggle(isOn: $useHardwareVolumeButtons) {
                    // Names the slider as well as the buttons — they're the
                    // same system volume, so the switch could never honour
                    // one and not the other. Names the exception too: it's a
                    // safety property, not a limitation. On Bluetooth or
                    // headphones that volume is the other device's.
                    SettingsRowText(title: "Use iPhone Volume Buttons", detail: "Volume buttons and the Lock Screen slider control the speaker instead of this device. Not while connected to Bluetooth or headphones.")
                }
                .tint(.accent)
            } icon: {
                SettingsIcon(symbol: "button.vertical.left.press.fill", colors: [Color(red: 0.95, green: 0.5, blue: 0.3), Color(red: 0.85, green: 0.35, blue: 0.2)])
            }
            // Super, like Lock Screen Now Playing it drives —
            // `HardwareVolumeControlModifier` and the Lock Screen path both
            // require it, so the row is editable in exactly the cases where
            // it changes anything.
            .gated(.hardwareVolumeButtons)
        }
    }
#endif

#if targetEnvironment(macCatalyst)
    /// Cue Mini controls speakers and nothing else.
    private var cueMiniSection: some View {
        Section {
            Button {
                openCueMini()
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
                    SettingsIcon(symbol: "arrow.up.forward.app", colors: [Color(red: 0.35, green: 0.85, blue: 0.55), Color(red: 0.25, green: 0.7, blue: 0.45)])
                }
            }
            .tint(.primary)

            Label {
                Toggle(isOn: $isMenuBarAppEnabled) {
                    Text("Launch with Cue")
                }
                .tint(.accent)
                .onChange(of: isMenuBarAppEnabled) { _, newValue in
                    if newValue {
                        openCueMini()
                    }
                }
            } icon: {
                SettingsIcon(symbol: "play.circle.fill", colors: [Color(red: 0.4, green: 0.85, blue: 0.95), Color(red: 0.25, green: 0.7, blue: 0.85)])
            }
        } header: {
            HStack {
                Text("Cue Mini (Menu Bar)")
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

    private func openCueMini() {
        Task {
            do {
                try await menuAppLaunchAtLoginManager.bridge?.openCueMiniApp()
            } catch {
                cueMiniErrorMessage = error.localizedDescription
                showCueMiniError = true
            }
        }
    }
#endif

    /// Turning speakers off moves playback back to this device first, so the
    /// route isn't left pointing at a group that is about to disappear. The
    /// speaker keeps playing its own queue; only Cue stops following it.
    private var sonosEnabledBinding: Binding<Bool> {
        Binding(
            get: { sonosService.isEnabled },
            set: { enabled in
                // The choice, not the route, which already reads as this
                // device on cellular while a speaker is still chosen.
                if !enabled, PlaybackRoute.shared.chosen != .device {
                    PlaybackRoute.shared.switchTo(.device, carrying: false)
                }
                withAnimation {
                    sonosService.setEnabled(enabled)
                }
            }
        )
    }
}
