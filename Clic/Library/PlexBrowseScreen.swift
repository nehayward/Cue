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
    @Environment(\.dismiss) var dismiss

    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(PlexBrowseService.self) private var plexBrowseService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService

    @State private var router = Router()
    @State private var isLoading: Bool = false

    var body: some View {
        @Bindable var plexBrowseService = plexBrowseService

        NavigationStack(path: $router.path) {
            List {
                PlexAuthorizationFlowView()
                if musicSearchService.isPlexAuthorized, musicSearchService.plexServerID != nil {
                    NavigationLink(value: RouterDestination.playableList(title: "Artists", action: { offset in
                        await plexBrowseService.artists(offset: offset)
                    })) {
                        Label("Artists", systemImage: "music.mic")
                    }
                    
                    NavigationLink(value: RouterDestination.playableList(title: "Albums", action: { offset in
                        await plexBrowseService.updateUserAlbums(offset: offset)
                    })) {
                        Label("Albums", systemImage: "smallcircle.circle.fill")
                    }
                    
                    NavigationLink(value: RouterDestination.playableList(title: "Songs", action: { offset in
                        await plexBrowseService.songs(offset: offset)
                    })) {
                        Label("Songs", systemImage: "music.note")
                    }
                    
                    NavigationLink(value: RouterDestination.playableGridScreen(title: "Playlists", items: $plexBrowseService.userPlaylists, action: { offset in
                        await plexBrowseService.updateUserPlaylists(offset: offset)
                    })) {
                        Label("Playlists (\(plexBrowseService.userPlaylists.count))", systemImage: "rectangle.stack.badge.play")
                    }
                    
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            ForEach(plexBrowseService.userPlaylists.prefix(4)) { item in
                                PlayableCardView(item: item)
                                    .containerRelativeFrame(.horizontal, count: 4, spacing: 12)
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    
                    if plexBrowseService.userPlaylists.isEmpty, isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    }
                }
                
            }
            .miniPlayerOnScrollHandler()
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("Plex Library")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: musicSearchService.plexServerID) {
                isLoading = true
                await updatePlexBrowseService()
                isLoading = false
            }
            .withAppRouter()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    MediaSelector()
                        .environment(router)
                }
            }
    #if !targetEnvironment(macCatalyst)
            .addDismiss {
                dismiss()
                Router.main.inspectorSheet = nil
            }
    #endif
        }
        .listStyle(.plain)
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            isLoading = true
            Task {
                await updatePlexBrowseService()
                isLoading = false
            }
        }
    }

    private func updatePlexBrowseService() async {
        await plexBrowseService.updateUserPlaylists()
    }
}

#Preview {
    BrowseScreen()
        .withEnvironments()
}

