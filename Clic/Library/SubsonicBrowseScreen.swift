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
                        action: { offset in await musicSearchService.subsonicArtists(offset: offset) }
                    )) {
                        Label("Artists", systemImage: "music.mic")
                    }
                    .listRowInsets(.default)
                    .listRowSeparator(.hidden)

                    NavigationLink(value: RouterDestination.playableList(
                        title: "Albums",
                        action: { offset in await musicSearchService.subsonicAlbums(offset: offset) }
                    )) {
                        Label("Albums", systemImage: "smallcircle.circle.fill")
                    }
                    .listRowInsets(.default)
                    .listRowSeparator(.hidden)

                    NavigationLink(value: RouterDestination.playableList(
                        title: "Songs",
                        action: { offset in await musicSearchService.subsonicSongs(offset: offset) }
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
