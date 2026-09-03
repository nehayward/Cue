import Defaults
import MusicSearchKit
import OrderedCollections
import SonosKit
import SwiftUI

/// A provider's own tab: the library's front page, with its collections as
/// rows. This is what the tab bar opens on iPhone, where the sidebar's
/// section would spill its tabs into "More".
struct ProviderRootTabScreen: View {
    let service: MediaSearchService

    /// One router per tab, never `Router.browse`: the Browse tab may be
    /// showing this same provider, and two `NavigationStack`s bound to one
    /// path push and pop each other.
    @State private var router = Router()

    var body: some View {
        switch service {
        case .plex:
            PlexBrowseScreen(showsMediaSelector: false, router: router)
        default:
            // Unreachable while `canBeTab` limits the tab view to providers
            // with collections; here rather than a crash if that changes.
            ContentUnavailableView(
                "\(service.title) Has No Tab Yet",
                systemImage: "square.grid.2x2",
                description: Text("Browse \(service.title) from the Browse tab.")
            )
        }
    }
}

/// One collection of an added provider — Artists, Albums, Songs or
/// Playlists — as a tab of its own. These are the tabs a provider's sidebar
/// section holds on iPad and Mac.
struct ProviderCollectionTabScreen: View {
    let service: MediaSearchService
    let collection: ProviderCollection

    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(PlexBrowseService.self) private var plexBrowseService

    @State private var router = Router()
    @State private var isLoading = false

    var body: some View {
        NavigationStack(path: $router.path) {
            content
                .navigationTitle(collection.title)
                .navigationBarTitleDisplayMode(.inline)
                .fontDesign(.rounded)
                .withAppRouter()
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }

    @ViewBuilder
    private var content: some View {
        switch service {
        case .plex:
            plexContent
        default:
            ContentUnavailableView(
                "\(service.title) Has No \(collection.title) Tab Yet",
                systemImage: collection.systemImage
            )
        }
    }

    // MARK: - Plex

    @ViewBuilder
    private var plexContent: some View {
        if musicSearchService.isPlexAuthorized, musicSearchService.plexServerID != nil {
            plexCollection
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            router.presentedSheet = .plexManagement
                        } label: {
                            Label("Manage Plex", systemImage: "server.rack")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
        } else {
            // Same rows the library's front page shows until a server and
            // library are picked: sign in, choose a connection, choose a
            // library. Every collection tab shows them, so whichever one the
            // sidebar lands on can finish the setup.
            List {
                PlexLibrarySelectionView()
            }
            .contentMargins(.horizontal, 16)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.presentedSheet = .plexManagement
                    } label: {
                        Label("Sign In to Plex", systemImage: "person.crop.circle")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var plexCollection: some View {
        @Bindable var plexBrowseService = plexBrowseService

        switch collection {
        case .artists:
            PlayableListView(title: "Artists", action: { offset in
                await plexBrowseService.artists(offset: offset)
            })
        case .albums:
            PlayableListView(title: "Albums", action: { offset in
                await plexBrowseService.updateUserAlbums(offset: offset)
            })
        case .songs:
            PlayableListView(
                title: "Songs",
                // Off, as on the library's front page: the index re-buckets
                // the list A–Z by title, which silently undoes every sort
                // but Title.
                showSectionIndex: false,
                sortOptions: PlexLibraryLists.songSortOptions(musicSearchService: musicSearchService),
                sortStorageKey: PlexLibraryLists.songSortKey,
                refreshAction: { musicSearchService.clearPlexSongCache() },
                searchAction: { query, offset in
                    await musicSearchService.searchPlexSongs(query: query, offset: offset)
                },
                loadingStatus: PlexLibraryLists.songSyncStatus(musicSearchService: musicSearchService)
            )
            .task(id: musicSearchService.plexServerID) {
                // Opening Songs is the moment to notice the server has more
                // songs than the synced copy.
                await musicSearchService.refreshPlexLibraryIfChanged()
            }
        case .playlists:
            PlayableGridScreen(items: $plexBrowseService.userPlaylists, action: { offset in
                await plexBrowseService.updateUserPlaylists(offset: offset)
            })
            .overlay {
                if isLoading, plexBrowseService.userPlaylists.isEmpty {
                    ProgressView()
                }
            }
            .task(id: musicSearchService.plexServerID) {
                // The grid only pages when a card scrolls into view, so an
                // empty one has to be filled from here.
                isLoading = true
                await plexBrowseService.updateUserPlaylists()
                isLoading = false
            }
        }
    }
}

#Preview {
    ProviderCollectionTabScreen(service: .plex, collection: .albums)
        .withEnvironments()
}
