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
    @Environment(CoreFeatures.self) var coreFeatures
    @Environment(FeatureGate.self) var featureGate
    
    var destination: RouterDestination? = nil
    
    @State private var router = Router()
    @State private var isShowingMailView = false
    @State private var refreshSonosLibrary = false
    
    @AppStorage("AppIcon") private var selectedAppIcon = "Default"
    
    @AppStorage(Defaults.AppStorageKeys.colorScheme) private var colorScheme: ColorSchemePreference = .system
#if DEBUG
    // Off until it's known whether the car's Now Playing follows without it
    // (`CarPlayInterface.start`).
    @AppStorage(Defaults.AppStorageKeys.carPlayMiniPlayer) private var carPlayMiniPlayer: Bool = false
    @AppStorage(Defaults.AppStorageKeys.nowPlayingSession) private var nowPlayingSession: Bool = false
    @State private var offline = OfflineMode.shared
    @AppStorage("dance.cue.debug.minimizeTabBar") private var minimizesTabBar: Bool = true
#endif
    @AppStorage(Defaults.AppStorageKeys.lastSeenWhatsNewVersion) private var lastSeenWhatsNewVersion: String = ""
    @AppStorage(Defaults.AppStorageKeys.latestReleaseVersion) private var latestReleaseVersion: String = ""
    @AppStorage(Defaults.AppStorageKeys.latestReleaseHeadline) private var latestReleaseHeadline: String = ""

    private var hasUnseenWhatsNew: Bool {
        // Strict: the worker must have returned 200 for this bundle's
        // version. No data → no banner, even when forcing for debug.
        guard !latestReleaseVersion.isEmpty else { return false }
        if WhatsNewDebug.forceShowBanner { return true }
        return lastSeenWhatsNewVersion != latestReleaseVersion
    }

    @State private var presentWhatsNew = false
    
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
                    if !featureGate.hasSuper {
                        PaywallButtonView()
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    } else {
                        Button {
                            HapticManager.shared.fireHaptic(.buttonPress)
                            router.presentedFullScreenCover = .paywall
                        } label: {
                            HStack(spacing: 12) {
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
                
                // One row a place, as the iPhone's Settings has it: what
                // each place holds is on its own page, so this list stays
                // short. The player's places first, then the speakers.
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
                                SettingsIcon(symbol: "music.note", colors: [Color(red: 0.95, green: 0.3, blue: 0.5), Color(red: 0.85, green: 0.2, blue: 0.4)])
                            }
                        }
                    }

                    NavigationLink(value: RouterDestination.settingsPage(.playback)) {
                        Label {
                            Text("Playback")
                        } icon: {
                            SettingsIcon(symbol: "play.square.fill", colors: [Color(red: 0.7, green: 0.5, blue: 0.95), Color(red: 0.55, green: 0.35, blue: 0.85)])
                        }
                    }

                    // Storage: the downloads and the caches, the one place
                    // for what takes room here. The same screen is Downloads
                    // from the library and Audiobooks.
                    NavigationLink(value: RouterDestination.settingsPage(.storage)) {
                        let downloads = DownloadManager.shared
                        LabeledContent {
                            Text(downloads.stoppedCount > 0
                                 ? "\(downloads.stoppedCount) stopped"
                                 : downloads.hasActiveDownloads
                                 ? "\(downloads.active.count) downloading"
                                 : formattedSize(Int(downloads.completedBytes)))
                        } label: {
                            Label {
                                Text("Storage")
                            } icon: {
                                SettingsIcon(symbol: "internaldrive.fill", colors: [Color(red: 0.55, green: 0.55, blue: 0.6), Color(red: 0.4, green: 0.4, blue: 0.45)])
                            }
                        }
                    }

                    if WatchSyncService.shared.isPaired {
                        NavigationLink {
                            WatchSettingsScreen()
                        } label: {
                            let watch = WatchSyncService.shared
                            LabeledContent {
                                if watch.isWatchAppInstalled, !watch.picks.items.isEmpty {
                                    Text(watch.picks.items.count == 1 ? "1 item" : "\(watch.picks.items.count) items")
                                }
                            } label: {
                                Label {
                                    Text("Apple Watch")
                                } icon: {
                                    SettingsIcon(symbol: "applewatch", colors: [Color(red: 0.4, green: 0.4, blue: 0.45), Color(red: 0.2, green: 0.2, blue: 0.25)], padding: 7)
                                }
                            }
                        }
                    }
                }

                Section {
                    NavigationLink(value: RouterDestination.settingsPage(.sonos)) {
                        LabeledContent {
                            if sonosService.isEnabled {
                                let isConnected = !sonosService.sonosPulse.isCancelled
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(isConnected ? .green : .red)
                                        .frame(width: 6, height: 6)
                                    Text(isConnected ? "Connected" : "Offline")
                                }
                            } else {
                                Text("Off")
                            }
                        } label: {
                            Label {
                                Text("Sonos")
                            } icon: {
                                SettingsIcon(symbol: "hifispeaker.fill", colors: [Color(red: 0.25, green: 0.25, blue: 0.3), Color(red: 0.1, green: 0.1, blue: 0.15)])
                            }
                        }
                    }
                }

                Section {
                    NavigationLink(value: RouterDestination.settingsPage(.appearance)) {
                        LabeledContent {
                            Text(colorScheme.rawValue.capitalized)
                        } label: {
                            Label {
                                Text("Appearance")
                            } icon: {
                                SettingsIcon(symbol: "circle.lefthalf.filled", colors: [Color(red: 0.55, green: 0.55, blue: 0.6), Color(red: 0.4, green: 0.4, blue: 0.45)])
                            }
                        }
                    }
                }

                Section {
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
                            SettingsIcon(symbol: "questionmark.circle", colors: [Color(red: 0.4, green: 0.7, blue: 0.95), Color(red: 0.25, green: 0.55, blue: 0.85)])
                        }
                    }
                    let message = "mailto:hi@cue.dance?subject=Support&body=\n\nVersion: \(OSEnvironment.versionInfo)\nID: \(subscriptionService.userID)"
                    // The whole row opens Mail, not only its words.
                    Link(destination: URL(string: message)!) {
                        Label {
                            HStack {
                                Text("Contact Support")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.up.forward")
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            SettingsIcon(symbol: "envelope.fill", colors: [Color(red: 0.95, green: 0.45, blue: 0.45), Color(red: 0.85, green: 0.3, blue: 0.35)])
                        }
                    }
                    .tint(.primary)
                    NavigationLink(value: RouterDestination.settingsPage(.about)) {
                        LabeledContent {
                            Text(OSEnvironment.versionInfo)
                        } label: {
                            Label {
                                Text("About")
                            } icon: {
                                SettingsIcon(symbol: "info.circle.fill", colors: [Color(red: 0.55, green: 0.55, blue: 0.6), Color(red: 0.4, green: 0.4, blue: 0.45)])
                            }
                        }
                    }
                }

#if DEBUG
                Section {
                    NavigationLink {
                        FeatureGateDebugView()
                            .withEnvironments()
                    } label: {
                        Label("Feature Gates", systemImage: "lock.open")
                    }
#if os(iOS) && !targetEnvironment(macCatalyst)
                    Toggle(isOn: $carPlayMiniPlayer) {
                        Label("CarPlay MiniPlayer", systemImage: "car")
                    }
#endif
                    Toggle(isOn: $nowPlayingSession) {
                        Label("Now Playing Session", systemImage: "play.rectangle")
                    }
                    // The offline app with the network up: the tab bar's
                    // swap and Search's, switched while Cue runs.
                    Toggle(isOn: $offline.simulatesOffline) {
                        Label("Simulate No Network", systemImage: "wifi.slash")
                    }
                    // Whether the tab bar shrinking as a page scrolls is
                    // what catches the scroll: switch it and compare.
                    Toggle(isOn: $minimizesTabBar) {
                        Label("Shrink Tab Bar on Scroll", systemImage: "dock.arrow.down.rectangle")
                    }
                } header: {
                    Text("Debug")
                } footer: {
#if os(iOS) && !targetEnvironment(macCatalyst)
                    Text("Off (the default in Debug builds for now) hides the MiniPlayer in CarPlay, to see whether the car's Now Playing then follows Cue's own player after Apple Music. Takes effect the next time the car connects.\n\nNow Playing Session puts the Lock Screen and car card for Plex, Subsonic and radio through a session of the player making the sound. Takes effect from the next song started.")
#else
                    Text("Now Playing Session puts the Now Playing card for Plex, Subsonic and radio through a session of the player making the sound. Takes effect from the next song started.")
#endif
                }
#endif
            }
            .animation(.smooth(duration: 0.35), value: hasUnseenWhatsNew)
            .navigationTitle("Settings")
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
            await subscriptionService.checkSubscription()
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
        featureGate.presentPaywall()
    }

    private var subscriptionStatusLine: Text {
        let info = subscriptionService.subscription.info
        var plan = info.flatMap { planName(for: $0.productIdentifier) }

        if plan == "Lifetime" {
            return Text("Lifetime")
        }
        // "Annual Free Trial · Renews …": the renewal is the first payment.
        if info?.isTrial == true {
            plan = [plan, "Free Trial"].compactMap { $0 }.joined(separator: " ")
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

    private func formattedSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
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
