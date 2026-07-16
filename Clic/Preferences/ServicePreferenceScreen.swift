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
    @AppStorage(Defaults.GroupStorageKeys.spotifyMusicTokenID, store: GroupStorageKeys.storage) private var spotifyMusicTokenID: String = ""
    @AppStorage(Defaults.GroupStorageKeys.appleMusicTokenID, store: GroupStorageKeys.storage) private var appleMusicTokenID: String = ""

    /// Sonos-side services discovered on the user's system.
    private var installedTypes: Set<SonosServiceType> {
        Set(servers.map(\.type))
    }

    /// Services the user can actually play from — authorized in Sonos, or
    /// needing no Sonos account (Library). Falls back to everything while
    /// discovery hasn't returned, so an empty keychain read never hides the
    /// toggles.
    private var connectedServices: [MediaSearchService] {
        guard !servers.isEmpty else { return MediaSearchService.allCases }
        return MediaSearchService.allCases.filter { $0.isAuthorized(on: installedTypes) }
    }

    /// Supported by Clic but not yet authorized on the user's Sonos. Only
    /// meaningful once discovery has returned something.
    private var notConnectedServices: [MediaSearchService] {
        guard !servers.isEmpty else { return [] }
        return MediaSearchService.allCases.filter { !$0.isAuthorized(on: installedTypes) }
    }

    /// Discovered on the user's Sonos but not supported by Clic yet —
    /// Pandora, SiriusXM, Bandcamp, etc. Shown dimmed like onboarding's
    /// ServicesStep so the list reflects everything the user has authorized.
    private var unsupportedKnownTypes: [SonosServiceType] {
        let supported = Set(MediaSearchService.allCases.compactMap(\.sonosServiceType))
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
                    Toggle(isOn: coreFeatures.enabledServices(service)) {
                        serviceToggleLabel(for: service)
                    }
                    .tint(.accent)
                }

                // Authorized in Sonos but not supported by Clic yet — same
                // dimmed informational treatment as onboarding's ServicesStep.
                ForEach(unsupportedKnownTypes, id: \.rawValue) { type in
                    Label {
                        VStack(alignment: .leading) {
                            Text(type.rawValue)
                            Text("Not supported in Clic yet")
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
                Text(servers.isEmpty ? "Supported Services" : "On Your Sonos")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(servers.isEmpty
                         ? "Requires authorization in the Sonos app."
                         : "Authorized in the Sonos app. Toggle to show or hide in Clic's search and browse.")
                    if unknownServiceCount > 0 {
                        Text(unknownServiceCount == 1
                             ? "1 other service we don't recognize yet."
                             : "\(unknownServiceCount) other services we don't recognize yet.")
                    }
                    if !unsupportedKnownTypes.isEmpty || unknownServiceCount > 0 {
                        Text("[Help us add support](https://clic.dance/help)")
                    }
                }
            }

            if !notConnectedServices.isEmpty {
                Section {
                    ForEach(notConnectedServices, id: \.self) { service in
                        Button {
                            openSonosApp()
                        } label: {
                            Label {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(service.title)
                                        Text("Sign in with the Sonos app")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.forward.app")
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

            if let server = servers.filter({ $0.type == .spotify }).first, servers.filter({ $0.type == .spotify }).count == 1 {
                Section {
                    Button {
                        Task {
                            await sonosService.setPrimaryServer(for: server)
                            primaryServices[server.type] = server
                            SpotifyBrowseService.shared.albums.removeAll()
                            SpotifyBrowseService.shared.playlists.removeAll()
                            SpotifyBrowseService.shared.tracks.removeAll()
                            spotifyMusicTokenID = server.id
                            GroupStorageKeys.storage?.synchronize()
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Override Spotify")
                                Text("Enable only if you're having connection issues with Spotify")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            MediaSearchService.spotify.iconForMusicService
                                .frame(width: 24, height: 24)
                        }
                        .tint(.accentColor)
                    }
                } header: {
                    Text("Troubleshooting")
                }
            }

            // "Can't find the service?" lives at the very bottom as plain
            // footer text — informational, not a section of its own.
            Section {
            } footer: {
                Text("Can't find the service here? To listen to music from providers not yet supported, like Pandora or SirusXM, make them a [favorite in the Sonos app](https://support.sonos.com/en-us/article/add-favorites-to-your-home-screen) then look for your stations in Clic search under \"[Sonos Favorites](clic://search/favorites).\"")
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

    /// The label inside a connected service's toggle. Spotify and Apple Music
    /// grow an account-picker menu when the Sonos system has more than one
    /// account for them; everyone else is a plain icon + title row.
    @ViewBuilder
    private func serviceToggleLabel(for service: MediaSearchService) -> some View {
        let spotifyServers = servers.filter { $0.type == .spotify }
        let appleServers = servers.filter { $0.type == .appleMusic }

        if service == .spotify, spotifyServers.count > 1 {
            Label {
                Menu {
                    ForEach(spotifyServers) { server in
                        Button {
                            Task {
                                await sonosService.setPrimaryServer(for: server)
                                primaryServices[server.type] = server
                                SpotifyBrowseService.shared.albums.removeAll()
                                SpotifyBrowseService.shared.playlists.removeAll()
                                SpotifyBrowseService.shared.tracks.removeAll()
                                spotifyMusicTokenID = server.id
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
                        Text("\(service.title) (\(spotifyServers.count))")
                        if let primaryServer = primaryServices[.spotify] {
                            Text(primaryServer.name.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.caption)
                        } else if let defaultService = spotifyServers.first?.name {
                            Text(defaultService)
                                .font(.caption)
                        }
                    }
                }
            } icon: {
                service.iconForMusicService
                    .frame(width: 24, height: 24)
            }
        } else if appleServers.count > 1, service == .apple {
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
            // Plex also needs a Clic-side sign-in — surface it right on the
            // row (like the Spotify/Apple account menus) instead of a
            // separate "Personalized Services" section. Single-line label so
            // the title lines up with the other rows; "Manage" is trailing
            // secondary text, not link-styled.
            Button {
                router.presentedSheet = .plexManagement
            } label: {
                Label {
                    HStack(spacing: 5) {
                        Text(service.title)
                            .foregroundStyle(.primary)
                        Image(systemName: musicSearchService.isPlexAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(musicSearchService.isPlexAuthorized ? AnyShapeStyle(.green.gradient) : AnyShapeStyle(.red.gradient.secondary))
                        Spacer()
                        Text(musicSearchService.isPlexAuthorized ? "Manage" : "Sign In")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    service.iconForMusicService
                        .frame(width: 24, height: 24)
                }
            }
            .buttonStyle(.plain)
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
