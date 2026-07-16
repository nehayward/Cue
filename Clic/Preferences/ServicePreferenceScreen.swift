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
            } header:  {
                Text(servers.isEmpty ? "Supported Services" : "On Your Sonos")
            } footer: {
                Text(servers.isEmpty
                     ? "Requires authorization in the Sonos app."
                     : "Authorized in the Sonos app. Toggle to show or hide in Clic's search and browse.")
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
            Section {
                Text("To listen to music from providers not yet supported, like Pandora or SirusXM, make them a [favorite in the Sonos app](https://support.sonos.com/en-us/article/add-favorites-to-your-home-screen) then look for your stations in Clic search under \"[Sonos Favorites](clic://search/favorites).\"")
            } header: {
                Text("Can't find the Service here?")
            }
            .headerProminence(.increased)

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
                            .frame(width: 24, height: 24)
                    }
                }
                if let server = servers.filter({ $0.type == .spotify }).first, servers.filter({ $0.type == .spotify }).count == 1 {
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
                }
            } header:  {
                Text("Personalized Services")
            } footer: {
                Text("Requires authorization in the **Sonos app** and **Clic**")
            }

#if !targetEnvironment(macCatalyst)
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
#endif
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
