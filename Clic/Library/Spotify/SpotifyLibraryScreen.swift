import Analytics
import CloudStorage
import MusicSearchKit
import NukeUI
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit
import TipKit

struct SpotifyLibraryScreen: View {
    @Environment(\.dismiss) var dismiss
    
    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(SpotifyBrowseService.self) private var spotifyBrowseService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService?
    
    @State private var router = Router.browse
    @State private var isLoading = true
    @State private var configStore = SectionConfigurationStores.shared.spotifyLibrary
    
    var body: some View {
        NavigationStack(path: $router.path) {
            List {
                ForEach(configStore.configuration.visibleSections(), id: \.self) { section in
                    sectionView(for: section)
                }
            }
            .listSectionSpacing(4)
            .listStyle(.plain)
            .headerProminence(.increased)
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("Spotify Library")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await updateSpotifyBrowseService()
            }
            .toolbar {
#if !os(visionOS)
                if #available(iOS 26.0, visionOS 26.0, *) {
                    ToolbarSpacer(.fixed)
                }
#endif
                ToolbarItem {
                    Button {
                        router.presentedSheet = .reorderSpotifyLibrarySections
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease")
                            .labelStyle(.iconOnly)
                    }
                }
#if !os(visionOS)
                if #available(iOS 26.0, visionOS 26.0, *) {
                    ToolbarSpacer(.fixed)
                }
#endif
                ToolbarItem {
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
            .refreshable {
                spotifyBrowseService.playlists.removeAll()
                spotifyBrowseService.tracks.removeAll()
                spotifyBrowseService.albums.removeAll()
                Task {
                    await updateSpotifyBrowseService(offset: 0)
                }
            }
            .withAppRouter()
        }
        .overlay {
            if isLoading, spotifyBrowseService.playlists.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            Task {
                await updateSpotifyBrowseService()
            }
        }
    }
    
    @ViewBuilder
    private func sectionView(for section: SpotifyLibrarySection) -> some View {
        switch section {
        case .likedSongs:
            Section {
                NavigationLink(value: RouterDestination.playableList(title: "Songs", playAllItem: .spotifyLikes, showSectionIndex: false, action: { offset in
                    await spotifyBrowseService.updateSongs()
                    return Array(spotifyBrowseService.tracks)
                })) {
                    Text("Liked Songs")
                        .fontDesign(.rounded)
                        .fontWeight(.semibold)
                }
                .tag(UUID().uuidString)
                LazyVGrid(columns: [.init(), .init()]) {
                    ForEach(spotifyBrowseService.tracks.prefix(7)) { item in
                        PlayableContentRowView(item: item)
                            .buttonStyle(.plain)
                            .geometryGroup()
                    }
                    if !spotifyBrowseService.tracks.isEmpty {
                        PlayAllButtonView(item: .spotifyLikes)
                            .transition(.identity)
                    }
                }
            }
            .listRowInsets(.default)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .task {
                await spotifyBrowseService.updateSongs(offset: 0, limit: 10)
            }
            .listRowSpacing(0)
            
        case .albums:
            Section {
                NavigationLink(value: RouterDestination.playableList(title: "Spotify Albums", showSectionIndex: false, action: { offset in
                    await spotifyBrowseService.userAlbums(offset: offset)
                    return Array(spotifyBrowseService.albums)
                })) {
                    Text("Albums")
                        .fontDesign(.rounded)
                        .fontWeight(.semibold)
                }
                .tag(UUID().uuidString)
                
                ForEach(spotifyBrowseService.albums.prefix(5)) { item in
                    PlayableContentRowView(item: item)
                        .padding(.bottom, 8)
                        .geometryGroup()
                }
            }
            .listRowInsets(.default)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .task {
                await spotifyBrowseService.userAlbums(offset: 0, limit: 10)
            }
            
        case .playlists:
            Section {
                NavigationLink(value: RouterDestination.playableList(title: "Spotify Playlists", showSectionIndex: false, action: { offset in
                    await spotifyBrowseService.updatePlaylists(offset: offset)
                    return Array(spotifyBrowseService.playlists)
                })) {
                    Text("Playlists")
                        .fontDesign(.rounded)
                        .fontWeight(.semibold)
                }
                .tag(UUID().uuidString)
                  
                LazyVGrid(columns: [.init(), .init()]) {
                    ForEach(spotifyBrowseService.playlists.prefix(8)) { item in
                        PlayableContentRowView(item: item)
                    }
                }
                .listRowInsets(.default)
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .task {
                await spotifyBrowseService.updatePlaylists(offset: 0, limit: 10)
            }
        }
    }
    
    private func updateSpotifyBrowseService(offset: Int = 0) async {
        isLoading = true
        defer { isLoading = false }
        await spotifyBrowseService.updatePlaylistsAndSongs(offset: offset)
    }
}

#Preview {
    SpotifyLibraryScreen()
        .withEnvironments()
}
