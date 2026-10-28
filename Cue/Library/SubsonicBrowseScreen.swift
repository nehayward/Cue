import OrderedCollections
import SwiftUI
import SonosKit
import MusicSearchKit

struct SubsonicBrowseScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(SonosService.self) private var sonosService
    @Environment(SubsonicBrowseService.self) private var subsonicBrowseService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService

    @State private var router = Router.browse
    @State private var isLoading = false
    @State private var hasLoadedOnce = false

    var body: some View {
        @Bindable var subsonicBrowseService = subsonicBrowseService

        NavigationStack(path: $router.path) {
            List {
                // Above the library, a section of its own.
                MusicLeftOffSection()
                if subsonicBrowseService.isAuthenticated {
                    // One group of rows, as on the Apple and Plex libraries.
                    NavigationLink(value: RouterDestination.playableList(
                        title: "Artists",
                        // Off for now: the index fights the paginated loads
                        // (scrolling to a letter jumps past unloaded pages).
                        showSectionIndex: false,
                        action: { offset in await musicSearchService.subsonicArtists(offset: offset) }
                    )) {
                        Label("Artists", systemImage: "music.mic")
                    }

                    NavigationLink(value: RouterDestination.playableList(
                        title: "Albums",
                        // Off for now: the index fights the paginated loads
                        // (scrolling to a letter jumps past unloaded pages).
                        showSectionIndex: false,
                        allowsGrid: true,
                        // Each option carries its own loader, so the list needs
                        // no separate default action.
                        sortOptions: albumSortOptions,
                        sortKey: SubsonicLibraryLists.albumSortKey,
                        searchAction: { query, offset in
                            await musicSearchService.searchSubsonicAlbums(query: query, offset: offset)
                        }
                    )) {
                        Label("Albums", systemImage: "smallcircle.circle.fill")
                    }

                    NavigationLink(value: RouterDestination.playableList(
                        title: "Songs",
                        // Off for now: the index fights the paginated loads
                        // (scrolling to a letter jumps past unloaded pages).
                        showSectionIndex: false,
                        sortOptions: songSortOptions,
                        sortKey: SubsonicLibraryLists.songSortKey,
                        refreshAction: { musicSearchService.clearSubsonicSongCache() },
                        searchAction: { query, offset in
                            await musicSearchService.searchSubsonicSongs(query: query, offset: offset)
                        },
                        loadingStatus: songSyncStatus
                    )) {
                        Label("Songs", systemImage: "music.note")
                    }

                    NavigationLink(value: RouterDestination.playableGridScreen(
                        title: "Playlists",
                        items: $subsonicBrowseService.userPlaylists,
                        action: { _ in }
                    )) {
                        Label("Playlists (\(subsonicBrowseService.userPlaylists.count))", systemImage: "rectangle.stack.badge.play")
                    }

                    if !subsonicBrowseService.userPlaylists.isEmpty {
                        ForEach(subsonicBrowseService.userPlaylists.prefix(5)) { item in
                            PlayableContentView(item: item)
                        }
                    } else if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }

                    // Recently Added as the Apple library shows it: the title
                    // opens the whole list, the newest under it out of the
                    // group.
                    Section {
                        NavigationLink(value: recentlyAddedDestination) {
                            Text("Recently Added")
                                .fontDesign(.rounded)
                                .fontWeight(.semibold)
                        }

                        PlayableContentGridView(items: subsonicBrowseService.recentAlbums, limit: 6)
                    }
                    .listSectionSpacing(0)
                    .listRowInsets(.default)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .musicLeftOffRoom()
            .overlay {
                if !subsonicBrowseService.isAuthenticated, !isLoading {
                    notConnectedView
                }
            }
            .animation(.default, value: subsonicBrowseService.userPlaylists)
            .animation(hasLoadedOnce ? .default : nil, value: subsonicBrowseService.recentAlbums)
            .contentMargins(.top, EdgeInsets(), for: .scrollContent)
            // Default placement, as on Plex's: `.scrollContent` insets the
            // rows but leaves the group's background running to the edge.
            .contentMargins(.horizontal, 16)
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("Subsonic")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                isLoading = true
                await subsonicBrowseService.load()
                isLoading = false
                hasLoadedOnce = true
            }
            .refreshable {
                await subsonicBrowseService.refresh()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsToolbarButton()
                        .environment(router)
                }
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
            .withAppRouter()
        }
        .overlay {
            if isLoading && !subsonicBrowseService.isAuthenticated {
                ProgressView()
            }
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            Task { await subsonicBrowseService.load() }
        }
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }

    /// Every album by when it was added, newest first.
    private var recentlyAddedDestination: RouterDestination {
        .playableList(
            title: "Recently Added",
            showSectionIndex: false,
            allowsGrid: true,
            action: { offset in await musicSearchService.subsonicRecentAlbums(offset: offset) }
        )
    }

    /// The line under the Songs title, shared with the Songs tab.
    private var songSyncStatus: () -> String? {
        SubsonicLibraryLists.songSyncStatus(musicSearchService: musicSearchService)
    }

    /// The Songs list's sort menu, shared with the Songs tab.
    private var songSortOptions: [PlayableListSort] {
        SubsonicLibraryLists.songSortOptions(musicSearchService: musicSearchService)
    }

    /// The Albums list's sort menu, shared with the Albums tab.
    private var albumSortOptions: [PlayableListSort] {
        SubsonicLibraryLists.albumSortOptions(musicSearchService: musicSearchService)
    }

    /// Shown when no server is configured yet. Centred (an overlay, not a list
    /// row) so it reads as an empty state rather than content jammed under the
    /// navigation bar, and it points people with no server at the projects
    /// that provide one.
    private var notConnectedView: some View {
        ContentUnavailableView {
            Label("No Server Connected", systemImage: "externaldrive.fill.badge.icloud")
        } description: {
            Text("Connect a Subsonic-compatible server to browse your own music library and play it here or on your Sonos speakers.")
        } actions: {
            VStack(spacing: 20) {
                Button {
                    router.presentedSheet = .subsonicManagement
                } label: {
                    Text("Connect Server")
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)

                VStack(spacing: 10) {
                    Text("Don't have a server yet?")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        serverProjectLink("Navidrome", address: "https://www.navidrome.org")
                        serverProjectLink("Airsonic", address: "https://airsonic.github.io")
                    }
                }
            }
        }
    }

    /// A link out to a self-hosted server project. Secondary (`.bordered`) on
    /// purpose — Connect Server stays the one prominent action on the screen.
    private func serverProjectLink(_ name: String, address: String) -> some View {
        Link(destination: URL(string: address)!) {
            HStack(spacing: 4) {
                Text(name)
                Image(systemName: "arrow.up.forward")
                    .font(.caption2)
            }
        }
        .buttonStyle(.bordered)
        .tint(.accent)
    }
}

#Preview {
    SubsonicBrowseScreen()
        .withEnvironments()
        .environment(SelectedGroupService(group: nil))
}
