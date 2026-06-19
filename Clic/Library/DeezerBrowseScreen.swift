import OrderedCollections
import SwiftUI
import SonosKit
import MusicSearchKit

struct DeezerBrowseScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(SonosService.self) private var sonosService
    @Environment(DeezerBrowseService.self) private var deezerBrowseService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService

    @State private var router = Router.browse
    @State private var isLoading = false
    @State private var hasLoadedOnce = false

    var body: some View {
        @Bindable var deezerBrowseService = deezerBrowseService

        NavigationStack(path: $router.path) {
            List {
                if deezerBrowseService.isAuthenticated {
                    NavigationLink(value: RouterDestination.playableList(
                        title: "Favorite Tracks",
                        showSectionIndex: false,
                        action: { offset in await musicSearchService.deezerUserFavoriteTracks(offset: offset) }
                    )) {
                        Label("Favorite Tracks", systemImage: "music.note")
                    }

                    NavigationLink(value: RouterDestination.playableList(
                        title: "Favorite Albums",
                        showSectionIndex: false,
                        action: { offset in await musicSearchService.deezerUserFavoriteAlbums(offset: offset) }
                    )) {
                        Label("Favorite Albums", systemImage: "smallcircle.circle.fill")
                    }

                    NavigationLink(value: RouterDestination.playableList(
                        title: "Favorite Artists",
                        showSectionIndex: false,
                        action: { offset in await musicSearchService.deezerUserFavoriteArtists(offset: offset) }
                    )) {
                        Label("Favorite Artists", systemImage: "music.mic")
                    }

                    NavigationLink(value: RouterDestination.playableGridScreen(
                        title: "Playlists",
                        items: $deezerBrowseService.userPlaylists,
                        action: { _ in }
                    )) {
                        Label("Playlists", systemImage: "music.note.list")
                    }

                    if !deezerBrowseService.userPlaylists.isEmpty {
                        ForEach(deezerBrowseService.userPlaylists.prefix(5)) { item in
                            PlayableContentView(item: item)
                        }
                    } else if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    }

                    if !deezerBrowseService.recentlyPlayed.isEmpty {
                        Section {
                            Text("Recently Played")
                                .fontDesign(.rounded)
                                .fontWeight(.semibold)

                            LazyVGrid(columns: [.init(), .init()]) {
                                ForEach(deezerBrowseService.recentlyPlayed.prefix(10)) { item in
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
                        Text("Add Deezer in the Sonos app to browse your library here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
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
            .animation(.default, value: deezerBrowseService.userPlaylists)
            .animation(hasLoadedOnce ? .default : nil, value: deezerBrowseService.recentlyPlayed)
            .contentMargins(.top, EdgeInsets(), for: .scrollContent)
            .miniPlayerOnScrollHandler()
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("Deezer")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                isLoading = true
                await deezerBrowseService.load()
                isLoading = false
                hasLoadedOnce = true
            }
            .refreshable {
                await deezerBrowseService.refresh()
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
            if isLoading && !deezerBrowseService.isAuthenticated {
                ProgressView()
            }
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            Task { await deezerBrowseService.load() }
        }
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }
}

#Preview {
    DeezerBrowseScreen()
        .withEnvironments()
        .environment(SelectedGroupService(group: nil))
}
