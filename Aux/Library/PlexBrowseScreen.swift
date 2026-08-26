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

    @State private var router = Router.browse
    @State private var isLoading: Bool = false
    @State private var plexAuthenticator = PlexAuthenticator.shared

    var body: some View {
        @Bindable var plexBrowseService = plexBrowseService

        NavigationStack(path: $router.path) {
            List {
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
                    
                    if !plexBrowseService.userPlaylists.isEmpty {
                        ForEach(plexBrowseService.userPlaylists.prefix(5)) { item in
                            PlayableContentView(item: item)
                        }
                    }
                    
                    if plexBrowseService.userPlaylists.isEmpty, isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    PlexLibrarySelectionView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .contentMargins(.top, EdgeInsets(), for: .scrollContent)
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
            .overlay {
                if plexAuthenticator.authToken == nil {
                    Button {
                        plexAuthenticator.authenticate()
                    } label: {
                        Text("Here")
                    }
                }
            }
    #if !targetEnvironment(macCatalyst)
            .addDismiss {
                dismiss()
                Router.main.inspectorSheet = nil
            }
    #endif
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            isLoading = true
            Task {
                await updatePlexBrowseService()
                isLoading = false
            }
        }
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }

    private func updatePlexBrowseService() async {
        await plexBrowseService.updateUserPlaylists()
    }
}

#Preview {
    BrowseScreen()
        .withEnvironments()
}

