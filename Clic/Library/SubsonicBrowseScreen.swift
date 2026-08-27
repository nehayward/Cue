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
                if subsonicBrowseService.isAuthenticated {
                    NavigationLink(value: RouterDestination.playableList(
                        title: "Artists",
                        // Off for now: the index fights the paginated loads
                        // (scrolling to a letter jumps past unloaded pages).
                        showSectionIndex: false,
                        action: { offset in await musicSearchService.subsonicArtists(offset: offset) }
                    )) {
                        Label("Artists", systemImage: "music.mic")
                    }
                    .listRowInsets(.default)
                    .listRowSeparator(.hidden)

                    NavigationLink(value: RouterDestination.playableList(
                        title: "Albums",
                        // Off for now: the index fights the paginated loads
                        // (scrolling to a letter jumps past unloaded pages).
                        showSectionIndex: false,
                        // Each option carries its own loader, so the list needs
                        // no separate default action.
                        sortOptions: albumSortOptions,
                        searchAction: { query, offset in
                            await musicSearchService.searchSubsonicAlbums(query: query, offset: offset)
                        }
                    )) {
                        Label("Albums", systemImage: "smallcircle.circle.fill")
                    }
                    .listRowInsets(.default)
                    .listRowSeparator(.hidden)

                    NavigationLink(value: RouterDestination.playableList(
                        title: "Songs",
                        // Off for now: the index fights the paginated loads
                        // (scrolling to a letter jumps past unloaded pages).
                        showSectionIndex: false,
                        sortOptions: songSortOptions,
                        searchAction: { query, offset in
                            await musicSearchService.searchSubsonicSongs(query: query, offset: offset)
                        },
                        loadingStatus: songSyncStatus
                    )) {
                        Label("Songs", systemImage: "music.note")
                    }
                    .listRowInsets(.default)
                    .listRowSeparator(.hidden)

                    NavigationLink(value: RouterDestination.playableList(
                        title: "Recently Added",
                        showSectionIndex: false,
                        action: { offset in await musicSearchService.subsonicRecentAlbums(offset: offset) }
                    )) {
                        Label("Recently Added", systemImage: "clock")
                    }
                    .listRowInsets(.default)
                    .listRowSeparator(.hidden)

                    NavigationLink(value: RouterDestination.playableGridScreen(
                        title: "Playlists",
                        items: $subsonicBrowseService.userPlaylists,
                        action: { _ in }
                    )) {
                        Label("Playlists", systemImage: "music.note.list")
                    }
                    .listRowInsets(.default)
                    .listRowSeparator(.hidden)

                    if !subsonicBrowseService.userPlaylists.isEmpty {
                        ForEach(subsonicBrowseService.userPlaylists.prefix(5)) { item in
                            PlayableContentView(item: item)
                                .listRowInsets(.default)
                                .listRowSeparator(.hidden)
                        }
                    } else if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    }

                    if !subsonicBrowseService.recentAlbums.isEmpty {
                        Section {
                            Text("Recently Added Albums")
                                .fontDesign(.rounded)
                                .fontWeight(.semibold)

                            LazyVGrid(columns: [.init(), .init()]) {
                                ForEach(subsonicBrowseService.recentAlbums.prefix(10)) { item in
                                    PlayableContentRowView(item: item)
                                        .buttonStyle(.plain)
                                        .geometryGroup()
                                }
                            }
                        }
                        .listRowInsets(.default)
                        .listRowSeparator(.hidden)
                        .listSectionSeparator(.hidden)
                    }

                }
            }
            .overlay {
                if !subsonicBrowseService.isAuthenticated, !isLoading {
                    notConnectedView
                }
            }
            .listSectionSpacing(4)
            .listStyle(.plain)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .animation(.default, value: subsonicBrowseService.userPlaylists)
            .animation(hasLoadedOnce ? .default : nil, value: subsonicBrowseService.recentAlbums)
            .contentMargins(.top, EdgeInsets(), for: .scrollContent)
            .miniPlayerOnScrollHandler()
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

    /// The line under the Songs title: how far the one-time library sync has
    /// got while it runs, and how big the library is once it is there. Songs
    /// is the only list that pulls the whole library in before it can show a
    /// row, so it is the only one that owes the user a count.
    private var songSyncStatus: () -> String? {
        {
            guard musicSearchService.isSyncingSubsonicSongs else {
                guard let count = musicSearchService.subsonicSongCount, count > 0 else { return nil }
                return count == 1 ? "1 song" : "\(count.formatted()) songs"
            }

            let synced = musicSearchService.subsonicSyncedSongCount
            guard let total = musicSearchService.subsonicLibrarySongCount, total > 0 else {
                // No total: the server won't report one, so a running count
                // is all there is to say.
                return synced == 0 ? "Loading library…" : "\(synced.formatted()) songs"
            }
            return "\(min(synced, total).formatted()) of \(total.formatted())"
        }
    }

    /// The Songs list's sort menu. Sorting happens on the synced copy of the
    /// library rather than on the server, which has no sort for songs.
    private var songSortOptions: [PlayableListSort] {
        SubsonicSongSort.allCases.map { sort in
            PlayableListSort(
                name: sort.label,
                ascendingLabel: sort.ascendingLabel,
                descendingLabel: sort.descendingLabel
            ) { offset, descending in
                await musicSearchService.subsonicSongs(offset: offset, sort: sort, descending: descending)
            }
        }
    }

    /// The Albums list's sort menu — these orders the server does provide, so
    /// each one is just a different `getAlbumList2` list type. No direction
    /// toggle: the list pages, and reversing a page is not reversing a list.
    private var albumSortOptions: [PlayableListSort] {
        SubsonicAlbumSort.allCases.map { sort in
            PlayableListSort(name: sort.label) { offset, _ in
                await musicSearchService.subsonicAlbums(offset: offset, sort: sort)
            }
        }
    }

    /// Shown when no server is configured yet. Centred (an overlay, not a list
    /// row) so it reads as an empty state rather than content jammed under the
    /// navigation bar, and it points people with no server at the projects
    /// that provide one.
    private var notConnectedView: some View {
        ContentUnavailableView {
            Label("No Server Connected", systemImage: "externaldrive.fill.badge.icloud")
        } description: {
            Text("Connect a Subsonic-compatible server to browse your own music library and play it on your Sonos speakers.")
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
        .ignoresSafeArea(.all, edges: .all)
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
