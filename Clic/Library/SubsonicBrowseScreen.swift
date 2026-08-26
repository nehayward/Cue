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

                } else if !isLoading {
                    Section {
                        VStack(spacing: 12) {
                            Text("Connect your Subsonic-compatible server (Navidrome, Airsonic, …) to browse your music here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button("Connect Server") {
                                router.presentedSheet = .subsonicManagement
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
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
}

#Preview {
    SubsonicBrowseScreen()
        .withEnvironments()
        .environment(SelectedGroupService(group: nil))
}
