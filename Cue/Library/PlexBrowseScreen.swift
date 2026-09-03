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
import AuthenticationServices

struct PlexBrowseScreen: View {
    @Environment(\.dismiss) var dismiss

    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(PlexBrowseService.self) private var plexBrowseService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService

    @State private var router: Router
    @State private var isLoading: Bool = false
    @State private var plexAuthenticator = PlexAuthenticator.shared

    /// Off when this screen is a provider tab of its own: the selector
    /// switches the Browse tab's provider, which this tab isn't.
    let showsMediaSelector: Bool

    /// - Parameter router: `Router.browse` for the Browse tab. A provider
    ///   tab passes its own, so its stack and the Browse tab's don't push
    ///   and pop each other when both are showing Plex.
    init(showsMediaSelector: Bool = true, router: Router = .browse) {
        self.showsMediaSelector = showsMediaSelector
        _router = State(initialValue: router)
    }

    /// The Songs list's sort menu, shared with the Songs tab.
    private var songSortOptions: [PlayableListSort] {
        PlexLibraryLists.songSortOptions(musicSearchService: musicSearchService)
    }

    /// The line under the Songs title, shared with the Songs tab.
    private var songSyncStatus: () -> String? {
        PlexLibraryLists.songSyncStatus(musicSearchService: musicSearchService)
    }

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
                    
                    NavigationLink(value: RouterDestination.playableList(
                        title: "Songs",
                        // Off for now, as on Subsonic: the index re-buckets
                        // the list A–Z by title, which silently undoes every
                        // sort but Title.
                        showSectionIndex: false,
                        sortOptions: songSortOptions,
                        sortKey: PlexLibraryLists.songSortKey,
                        refreshAction: { musicSearchService.clearPlexSongCache() },
                        searchAction: { query, offset in
                            await musicSearchService.searchPlexSongs(query: query, offset: offset)
                        },
                        loadingStatus: songSyncStatus
                    )) {
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
            // Default placement, not `.scrollContent`: the scoped form insets
            // the rows but leaves the List's section background running to the
            // scroll view's edge, so the card butted straight up against the
            // sidebar with no gap.
            .contentMargins(.horizontal, 16)
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("Plex Library")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: musicSearchService.plexServerID) {
                isLoading = true
                await updatePlexBrowseService()
                isLoading = false
                // Opening the library is the moment to notice the server has
                // more songs than the synced copy — Songs is one tap away.
                await musicSearchService.refreshPlexLibraryIfChanged()
            }
            .refreshable {
                // Songs is served from a synced copy of the library; a
                // refresh should pick up anything added on the server since.
                musicSearchService.clearPlexSongCache()
                await updatePlexBrowseService()
            }
            .withAppRouter()
            .toolbar {
                if showsMediaSelector {
                    ToolbarItem(placement: .topBarTrailing) {
                        MediaSelector()
                            .environment(router)
                    }
                } else {
                    // The selector's menu is also where Plex is managed from
                    // the Browse tab; a provider tab needs its own way in.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            router.presentedSheet = .plexManagement
                        } label: {
                            Label("Manage Plex", systemImage: "server.rack")
                                .labelStyle(.iconOnly)
                        }
                    }
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

