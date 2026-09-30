import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit

/// Services preferences, aware of what the user has actually authorized in
/// Sonos. Services discovered on the Sonos system get the usual show/hide
/// toggles; everything else drops into a dimmed "Available with Sonos"
/// section that deep-links to the Sonos app to sign in. Until discovery
/// returns anything (cold keychain, no system found) every service keeps its
/// toggle so nobody gets locked out by a slow read — pull to refresh re-runs
/// discovery.
struct ServicePreferenceScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(CoreFeatures.self) private var coreFeatures

    @State private var servers: [MediaServer] = []
    @State private var primaryServices: [SonosServiceType: MediaServer] = [:]
    @AppStorage(Defaults.GroupStorageKeys.appleMusicTokenID, store: GroupStorageKeys.storage) private var appleMusicTokenID: String = ""
    /// How Plex and Subsonic hand audio over — see `StreamTranscoding`. The
    /// bitrate default matches the one the package falls back to when unset.
    @AppStorage(Defaults.AppStorageKeys.streamTranscodeFormat) private var transcodeFormat: StreamTranscoding.Format = .original
    @AppStorage(Defaults.AppStorageKeys.streamTranscodeBitrate) private var transcodeBitrate: Int = StreamTranscoding.defaultBitrate

    /// Sonos-side services discovered on the user's system.
    private var installedTypes: Set<SonosServiceType> {
        Set(servers.map(\.type))
    }

    /// Self-hosted services set up entirely inside Cue. They have no Sonos
    /// account at all, so they get their own section instead of sitting under
    /// a header that says the opposite.
    private var selfHostedServices: [MediaSearchService] {
        MediaSearchService.supported.filter { $0.isConfiguredInCue != nil }
    }

    /// Everything that does go through a Sonos account.
    private var sonosServices: [MediaSearchService] {
        MediaSearchService.supported.filter { $0.isConfiguredInCue == nil }
    }

    /// Services the user can actually play from — authorized in Sonos, or
    /// needing no Sonos account (Library). Falls back to everything while
    /// discovery hasn't returned, so an empty keychain read never hides the
    /// toggles.
    private var connectedServices: [MediaSearchService] {
        guard !servers.isEmpty else { return sonosServices }
        return sonosServices.filter { $0.isAuthorized(on: installedTypes) }
    }

    /// Supported by Cue but not yet authorized on the user's Sonos. Only
    /// meaningful once discovery has returned something.
    private var notConnectedServices: [MediaSearchService] {
        guard !servers.isEmpty else { return [] }
        return sonosServices.filter { !$0.isAuthorized(on: installedTypes) }
    }

    /// Discovered on the user's Sonos but not supported by Cue yet —
    /// Pandora, SiriusXM, Bandcamp, etc. Shown dimmed like onboarding's
    /// ServicesStep so the list reflects everything the user has authorized.
    private var unsupportedKnownTypes: [SonosServiceType] {
        let supported = Set(MediaSearchService.supported.compactMap(\.sonosServiceType))
        return installedTypes.filter { type in
            guard !supported.contains(type) else { return false }
            if case .unknown = type { return false }
            return true
        }.sorted { $0.rawValue.localizedStandardCompare($1.rawValue) == .orderedAscending }
    }

    /// Discovered `.unknown(_)` services we can't render a name for —
    /// surfaced as a footer count, matching onboarding.
    private var unknownServiceCount: Int {
        installedTypes.filter { type in
            if case .unknown = type { return true }
            return false
        }.count
    }

    var body: some View {
        @Bindable var coreFeatures = coreFeatures
        List {
            Section {
                ForEach(connectedServices, id: \.self) { service in
                    if let managementSheet = service.managementSheet {
                        // Whole cell opens the service's management sheet; the
                        // trailing switch still handles its own touches.
                        Toggle(isOn: coreFeatures.enabledServices(service)) {
                            serviceToggleLabel(for: service)
                        }
                        .tint(.accent)
                        .contentShape(.rect)
                        .onTapGesture {
                            router.presentedSheet = managementSheet
                        }
                    } else {
                        Toggle(isOn: coreFeatures.enabledServices(service)) {
                            serviceToggleLabel(for: service)
                        }
                        .tint(.accent)
                    }
                }

                // Authorized in Sonos but not supported by Cue yet — same
                // dimmed informational treatment as onboarding's ServicesStep.
                ForEach(unsupportedKnownTypes, id: \.rawValue) { type in
                    Label {
                        VStack(alignment: .leading) {
                            Text(type.rawValue)
                            Text("Not supported in Cue yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .opacity(0.6)
                }
            } header:  {
                Text(servers.isEmpty ? "Music Services" : "On Your Sonos")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    // No speakers read means these play on this device, so
                    // the Sonos app has nothing to do with them.
                    Text(servers.isEmpty
                         ? "Toggle to show or hide in Cue's search and browse."
                         : "Authorized in the Sonos app. Toggle to show or hide in Cue's search and browse.")
                    if unknownServiceCount > 0 {
                        Text(unknownServiceCount == 1
                             ? "1 other service we don't recognize yet."
                             : "\(unknownServiceCount) other services we don't recognize yet.")
                    }
                    if !unsupportedKnownTypes.isEmpty || unknownServiceCount > 0 {
                        Text("[Help us add support](https://cue.dance/help)")
                    }
                }
            }

            if !selfHostedServices.isEmpty {
                Section {
                    ForEach(selfHostedServices, id: \.self) { service in
                        // Connected ones get the same show/hide toggle as
                        // everything else; the rest offer the setup sheet.
                        if service.isConfiguredInCue == true {
                            Toggle(isOn: coreFeatures.enabledServices(service)) {
                                serviceToggleLabel(for: service)
                            }
                            .tint(.accent)
                            .contentShape(.rect)
                            .onTapGesture {
                                guard let sheet = service.managementSheet else { return }
                                router.presentedSheet = sheet
                            }
                        } else {
                            connectRow(for: service)
                        }
                    }
                } header: {
                    Text("Self-Hosted")
                } footer: {
                    Text("Set up here in Cue — these need no Sonos app sign-in. Your speakers stream straight from your own server; a folder of files plays on this device.")
                }

                streamingQualitySection
            }

            if !notConnectedServices.isEmpty {
                Section {
                    ForEach(notConnectedServices, id: \.self) { service in
                        connectRow(for: service)
                    }
                } header: {
                    Text("Available with Sonos")
                } footer: {
                    Text("Add these in the Sonos app, then pull down here to refresh.")
                }
            }
//            #if DEBUG
//            Section("Discovered") {
//                ForEach(servers) { server in
//                    VStack(alignment: .leading) {
//                        Text(server.type.rawValue)
//                        Text(server.name)
//                        Text(server.id)
//                        Text("\(server.token)")
//                            .textSelection(.enabled)
//                        Text("Region: \(Locale.current.region?.identifier ?? "Unknown")")
//                        Text("Current: \(Locale.current.region?.identifier ?? "US" == "US" ? "3079" : "2311")")
//                    }
//                }
//            }
//            #endif
#if !targetEnvironment(macCatalyst)
            Section {
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
#endif

            // "Can't find the service?" lives at the very bottom as plain
            // footer text — informational, not a section of its own.
            // About Sonos Favorites, so only with Sonos switched on.
            if sonosService.isEnabled {
            Section {
            } footer: {
                Text("Can't find the service here? To listen to music from providers not yet supported, like Pandora or SirusXM, make them a [favorite in the Sonos app](https://support.sonos.com/en-us/article/add-favorites-to-your-home-screen) then look for your stations in Cue search under \"[Sonos Favorites](cue://search/favorites).\"")
            }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadServers()
        }
        .task {
            await loadServers()
        }
    }

    /// Transcoding for the self-hosted servers: the original file, or MP3 /
    /// Opus at a bitrate cap, applied by the server as it streams. Sonos
    /// players don't decode Opus, so a speaker gets MP3 in its place; Plex
    /// on a speaker is Plex's own Sonos service and isn't touched here.
    private var streamingQualitySection: some View {
        Section {
            Picker("Format", selection: $transcodeFormat) {
                ForEach(StreamTranscoding.Format.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            if transcodeFormat != .original {
                Picker("Bitrate", selection: $transcodeBitrate) {
                    ForEach(StreamTranscoding.bitrates, id: \.self) { bitrate in
                        Text("\(bitrate) kbps").tag(bitrate)
                    }
                }
            }
        } header: {
            Text("Streaming Quality")
        } footer: {
            Text(streamingQualityFooter)
        }
    }

    private var streamingQualityFooter: String {
        switch transcodeFormat {
        case .original:
            "Plex and Subsonic songs stream as the original files. Choose MP3 or Opus to have your server convert them on the way out — smaller over cellular or a slow connection home. Applies to songs played and downloaded on this device, and to Subsonic songs sent to your speakers."
        case .mp3:
            "Songs played and downloaded on this device, and Subsonic songs sent to your speakers, arrive as MP3 at up to the bitrate above. Plex plays on speakers through its own Sonos service, at the quality set on your Plex server."
        case .opus:
            "Songs played and downloaded on this device arrive as Opus. Sonos players can't play Opus, so Subsonic songs sent to a speaker are converted to MP3 at the same bitrate instead. Plex plays on speakers through its own Sonos service, at the quality set on your Plex server."
        }
    }

    /// A service that isn't set up yet. Self-hosted ones open their setup
    /// sheet in Cue; the rest send the user to the Sonos app to sign in.
    private func connectRow(for service: MediaSearchService) -> some View {
        let isSelfHosted = service.isConfiguredInCue != nil

        return Button {
            if isSelfHosted, let sheet = service.managementSheet {
                router.presentedSheet = sheet
            } else {
                openSonosApp()
            }
        } label: {
            Label {
                HStack {
                    VStack(alignment: .leading) {
                        Text(service.title)
                        Text(service == .files
                             ? "Choose a folder of music"
                             : (isSelfHosted ? "Connect your server" : "Sign in with the Sonos app"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isSelfHosted ? "chevron.right" : "arrow.up.forward.app")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                service.iconForMusicService
                    .frame(width: 24, height: 24)
                    .grayscale(1)
                    .opacity(0.6)
            }
            .tint(.primary)
        }
    }

    /// The label inside a connected service's toggle. Apple Music grows an
    /// account-picker menu when the Sonos system has more than one account
    /// for it; everyone else is a plain icon + title row.
    @ViewBuilder
    private func serviceToggleLabel(for service: MediaSearchService) -> some View {
        let appleServers = servers.filter { $0.type == .appleMusic }

        if appleServers.count > 1, service == .apple {
            Label {
                Menu {
                    ForEach(appleServers) { server in
                        Button {
                            Task {
                                await sonosService.setPrimaryServer(for: server)
                                primaryServices[server.type] = server
                                appleMusicTokenID = server.id
                                GroupStorageKeys.storage?.synchronize()
                            }
                        } label: {
                            VStack {
                                Text(server.name)
                                Text(server.id)
                            }
                        }
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text("\(service.title) (\(appleServers.count))")
                        if let primaryServer = primaryServices[.appleMusic] {
                            Text(primaryServer.name.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.caption)
                        } else if let defaultService = appleServers.first?.name {
                            Text(defaultService)
                                .font(.caption)
                        }
                    }
                }
            } icon: {
                service.iconForMusicService
                    .frame(width: 24, height: 24)
            }
        } else if service == .plex {
            // Plex also needs a Cue-side sign-in — surfaced on the row
            // itself. Bare Label, structured exactly like the default branch
            // so the leading edge lines up; the whole cell is tappable (see
            // the onTapGesture where the row is built) with "Manage" as
            // trailing secondary text.
            Label {
                Text(service.title)
                Text(musicSearchService.isPlexAuthorized ? "Manage" : "Sign In")
                    .foregroundStyle(.accent)
            } icon: {
                service.iconForMusicService
                    .frame(width: 24, height: 24)
            }
        } else if service == .subsonic {
            // Subsonic is configured entirely in Cue — same tappable-cell
            // treatment as Plex.
            Label {
                Text(service.title)
                Text(musicSearchService.isSubsonicConfigured ? "Manage" : "Connect")
                    .foregroundStyle(.accent)
            } icon: {
                service.iconForMusicService
                    .frame(width: 24, height: 24)
            }
        } else if service == .files {
            // A folder rather than a server; the row names it.
            Label {
                Text(service.title)
                Text(FilesLibraryService.shared.folderName ?? "Choose Folder")
                    .foregroundStyle(.accent)
            } icon: {
                service.iconForMusicService
                    .frame(width: 24, height: 24)
            }
        } else {
            Label {
                Text("\(service.title)\(!service.isBrowseSupported ? " (Search Only)" : "")")
            } icon: {
                service.iconForMusicService
                    .frame(width: 24, height: 24)
            }
        }
    }

    /// Re-reads the Sonos media-server list and, when discovery returns
    /// anything, turns off services the user no longer has authorized —
    /// never the other way around, so manual "off" choices stick.
    @MainActor
    private func loadServers() async {
        servers = await sonosService.services()
        for server in servers {
            if let primaryService = await sonosService.getPrimaryService(for: server.type) {
                primaryServices[server.type] = primaryService
            }
        }
        guard !servers.isEmpty else { return }
        coreFeatures.disableUnauthorizedServices(from: installedTypes)
    }

    /// Same deep link as onboarding's ServicesStep: open the Sonos app so the
    /// user can authorize a service, falling back to its App Store page.
    private func openSonosApp() {
        #if canImport(UIKit)
        if let url = URL(string: "sonos://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let store = URL(string: "https://apps.apple.com/app/sonos/id1488977981") {
            UIApplication.shared.open(store)
        }
        #endif
    }
}

#Preview {
    NavigationStack {
        ServicePreferenceScreen()
    }
    .withEnvironments()
}
