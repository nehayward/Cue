import Analytics
import CloudStorage
import MusicSearchKit
import Defaults
import NukeUI
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit
import Defaults
import TipKit
import AuthenticationServices

struct PlexBrowseScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(PlexBrowseService.self) private var plexBrowseService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService

    @State private var router = Router()

    var body: some View {
        @Bindable var plexBrowseService = plexBrowseService

        NavigationStack(path: $router.path) {
            ScrollView {
                PlexAuthorizationFlowView()
                VStack(alignment: .leading) {
                    if musicSearchService.isPlexAuthorized, musicSearchService.plexServerID != nil {
                        Section {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                                ForEach(plexBrowseService.userPlaylists.prefix(4)) { item in
                                    PlayableCardView(item: item)
                                }
                            }
                        } header: {
                            HStack {
                                Text("Playlists (\(plexBrowseService.userPlaylists.count))")
                                Spacer()
                                NavigationLink(value: RouterDestination.playableGridScreen(title: "Playlists", items: $plexBrowseService.userPlaylists, action: { offset in
                                    await plexBrowseService.updateUserPlaylists(offset: offset)
                                })) {
                                    Text("Show all \(Image(systemName: "chevron.right"))")
                                }
                            }
                            .foregroundStyle(.secondary)
                            .padding(.vertical)
                        }
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .withAppRouter(router: router)
            .navigationTitle("Plex Library")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: musicSearchService.plexServerID) {
                await updatePlexBrowseService()
            }
            .addDismiss(action: dismiss.callAsFunction)
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            Task {
                await updatePlexBrowseService()
            }
        }
    }

    @MainActor
    private func updatePlexBrowseService() async {
        await plexBrowseService.updateUserPlaylists()
    }
}

#Preview {
    BrowseScreen()
        .withEnvironments()
}

