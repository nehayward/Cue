import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit

struct ServicePreferenceScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(CoreFeatures.self) private var coreFeatures

    @State private var servers: [MediaServer] = []
    @State private var primaryServices: [SonosServiceType: MediaServer] = [:]
    @AppStorage(Defaults.AppStorageKeys.spotifyLocale) private var overrideSpotifyLocale: Bool = false

    var body: some View {
        @Bindable var coreFeatures = coreFeatures
        List {
            Section {
                ForEach(MediaSearchService.allCases, id: \.self) { service in
                    Toggle(isOn: coreFeatures.enabledServices(service)) {
                        let servers = servers.filter { $0.type == .spotify }
                        if service == .spotify, servers.count > 1 {
                            Label {
                                Menu {
                                    ForEach(servers) { server in
                                        Button {
                                            Task {
                                                await sonosService.setPrimaryServer(for: server)
                                                primaryServices[server.type] = server
                                                SpotifyBrowseService.shared.albums.removeAll()
                                                SpotifyBrowseService.shared.playlists.removeAll()
                                                SpotifyBrowseService.shared.tracks.removeAll()
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
                                        Text("\(service.title) (\(servers.count))")
                                        if let primaryServer = primaryServices[.spotify] {
                                            Text(primaryServer.name.trimmingCharacters(in: .whitespacesAndNewlines))
                                                .font(.caption)
                                        } else if let defaultService = servers.first(where: { $0.type == .spotify })?.name {
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
                    .tint(.accent)
                }
            } header:  {
                Text("Supported Services")
            } footer: {
                Text("Requires authorization in the Sonos app.")
            }
            if UIApplication.shared.isRunningInTestFlightEnvironment() {
                Section("Discovered") {
                    ForEach(servers) { server in
                        VStack(alignment: .leading) {
                            Text(server.type.rawValue)
                            Text(server.name)
                            Text(server.id)
                            Text("Region: \(Locale.current.region?.identifier ?? "Unknown")")
                            Text("Current: \(Locale.current.region?.identifier ?? "US" == "US" ? "3079" : "2311")")
                        }
                    }
                }
            }
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
                Toggle(isOn: $overrideSpotifyLocale) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Override Spotify Locale")
                            Text("Enable only if you're having connection issues with Spotify")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        MediaSearchService.spotify.iconForMusicService
                            .frame(width: 24, height: 24)
                    }
                }
                .tint(.accentColor)
                .onChange(of: overrideSpotifyLocale) {
                    UserDefaults.standard.synchronize()
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
        .task {
            servers = await sonosService.services()
            for server in servers {
                if let primaryService = await sonosService.getPrimaryService(for: server.type) {
                    primaryServices[server.type] = primaryService
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ServicePreferenceScreen()
    }
    .withEnvironments()
}
