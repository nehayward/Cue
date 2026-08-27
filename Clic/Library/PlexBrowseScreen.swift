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

    @State private var router = Router.browse
    @State private var isLoading: Bool = false
    @State private var plexAuthenticator = PlexAuthenticator.shared

    /// The Songs list's sort menu. Every option is a Plex `sort` field, so
    /// the server does the ordering and each page comes back already in it —
    /// no local copy of the library, and reversing works on the whole list
    /// rather than the page in front of you.
    private var songSortOptions: [PlayableListSort] {
        PlexSongSort.allCases.map { sort in
            PlayableListSort(
                name: sort.label,
                ascendingLabel: sort.ascendingLabel,
                descendingLabel: sort.descendingLabel
            ) { offset, reversed in
                await musicSearchService.plexSongs(offset: offset, sort: sort, reversed: reversed)
            }
        }
    }

    /// The line under the Songs title: how far the one-time library sync has
    /// got while it runs, and how big the library is once it is there.
    private var songSyncStatus: () -> String? {
        {
            guard musicSearchService.isSyncingPlexSongs else {
                guard let count = musicSearchService.plexSongCount, count > 0 else { return nil }
                return count == 1 ? "1 song" : "\(count.formatted()) songs"
            }

            let synced = musicSearchService.plexSyncedSongCount
            guard let total = musicSearchService.plexLibrarySongCount, total > 0 else {
                return synced == 0 ? "Loading library…" : "\(synced.formatted()) songs"
            }
            return "\(min(synced, total).formatted()) of \(total.formatted())"
        }
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
                        sortOptions: songSortOptions,
                        sortKey: "plex.songs",
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
            .refreshable {
                // Songs is served from a synced copy of the library; a
                // refresh should pick up anything added on the server since.
                musicSearchService.clearPlexSongCache()
                await updatePlexBrowseService()
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

