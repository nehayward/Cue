import SwiftUI
import SonosKit
import MusicSearchKit

struct ServicePreferenceScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(CoreFeatures.self) private var coreFeatures

    var body: some View {
        @Bindable var coreFeatures = coreFeatures
        List {
            Section {
                ForEach(MediaSearchService.allCases, id: \.self) { service in
                    Toggle(isOn: coreFeatures.enabledServices(service)) {
                        Label {
                            Text("\(service.title)\(!service.isBrowseSupported ? " (Search Only)" : "")")
                        } icon: {
                            service.iconForMusicService
                                .frame(width: 24, height: 24)
                        }
                    }
                    .tint(.accent)
                }
            } header:  {
                Text("Supported Services")
            } footer: {
                Text("Requires authorization in the Sonos app.")
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
                            .frame(width: 20, height: 20)
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
    }
}

#Preview {
    NavigationStack {
        ServicePreferenceScreen()
    }
    .withEnvironments()
}
