import CloudStorage
import MusicSearchKit
import NukeUI
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit

struct AppleLibraryBrowseScreen: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(AppleMusicBrowseService.self) private var appleMusicBrowseService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService
    @Environment(\.dismiss) var dismiss
    
    @State private var router = Router.browse
    @State private var isLoading = true
    @State private var configStore = SectionConfigurationStores.shared.appleLibrary
    
    private var numberOfItemsInGrid: Int {
        return 6
    }
    
    var body: some View {
        @Bindable var appleMusicBrowseService = appleMusicBrowseService
        @Bindable var sonosService = sonosService
        
        NavigationStack(path: $router.path) {
            List {
                // Above the library, a section of its own.
                MusicLeftOffSection()
                ForEach(configStore.configuration.visibleSections(), id: \.self) { section in
                    sectionView(for: section)
                }
            }
            .musicLeftOffRoom()
#if targetEnvironment(macCatalyst)
            .listStyle(.plain)
#endif
            .contentMargins(.top, EdgeInsets(), for: .scrollContent)
            .librarySideMargins(for: .scrollContent)
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("Apple Library")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await updateAppleMusicBrowseService()
            }
            // Read again once Apple Music may be asked: on a new install the
            // first read comes while onboarding holds the alert, and reads
            // nothing.
            .onReceive(NotificationCenter.default.publisher(for: AppleMusicPermission.didChange)) { _ in
                Task { await updateAppleMusicBrowseService() }
            }
            .withAppRouter()
            .toolbar {
                // In the bar while the page reads, not over its sections.
                if isLoading {
                    ToolbarItem(placement: .primaryAction) {
                        ProgressView()
                    }
                }
                // The gear every provider's browse screen has; this one was
                // missed when they got it.
                ToolbarItem(placement: .topBarLeading) {
                    SettingsToolbarButton()
                        .environment(router)
                }
#if !os(visionOS)
                if #available(iOS 26.0, visionOS 26.0, *) {
                    ToolbarSpacer(.fixed)
                }
#endif
                ToolbarItem {
                    Button {
                        router.presentedSheet = .reorderAppleLibrarySections
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
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            Task {
                await updateAppleMusicBrowseService()
            }
        }
    }
    
    @ViewBuilder
    private func sectionView(for section: AppleLibrarySection) -> some View {
        @Bindable var appleMusicBrowseService = appleMusicBrowseService
        
        switch section {
        case .artists:
            NavigationLink(value: RouterDestination.appleLibrary(.artists)) {
                Label("Artists", systemImage: "music.mic")
                    .foregroundStyle(.primary)
            }
        case .albums:
            NavigationLink(value: RouterDestination.appleLibrary(.albums)) {
                Label("Albums", systemImage: "smallcircle.circle.fill")
            }
            
        case .songs:
            NavigationLink(value: RouterDestination.appleLibrary(.songs)) {
                Label("Songs", systemImage: "music.note")
            }

        case .favorites:
            // A row like Playlist Folders', opening the favorite playlists
            // (Favorite Songs among them), albums and artists: a grid at
            // first, with the other lists' sort menu and list/grid button.
            NavigationLink(value: RouterDestination.appleLibrary(.favorites)) {
                Label("Favorites", systemImage: "star.fill")
            }

        case .playlistFolders:
            NavigationLink(value: RouterDestination.playableGridScreen(title: "Playlist Folders", items: $appleMusicBrowseService.userPlaylistFolders, action: { offset in
                await appleMusicBrowseService.updateUsersApplePlaylistFolders(offset: offset)
            })) {
                Label("Playlist Folders", systemImage: "folder.fill")
            }
            
        case .playlists:
            ApplePlaylistsView()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        case .recentlyPlayed:
            Section {
                NavigationLink(value: RouterDestination.playableGridScreen(title: "Recently Played", items: $appleMusicBrowseService.usersRecents, action: { offset in
                    await appleMusicBrowseService.updateUsersRecentPlayed(offset: offset)
                })) {
                    Text("Recently Played")
                        .fontDesign(.rounded)
                        .fontWeight(.semibold)
                }
                // Stable: a fresh UUID re-tagged the row on every pass.
                .tag("appleRecentlyPlayedHeader")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                
                PlayableContentGridView(items: Array(appleMusicBrowseService.usersRecents), limit: 6)
            }
            .listSectionSpacing(0)
            .listRowInsets(.default)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            
        case .recentlyAdded:
            Section {
                NavigationLink(value: RouterDestination.playableGridScreen(title: "Recently Added", items: $appleMusicBrowseService.usersRecentsAdded, action: { offset in
                    await appleMusicBrowseService.updateUsersRecentAddedTracks(offset: offset)
                })) {
                    Text("Recently Added")
                        .fontDesign(.rounded)
                        .fontWeight(.semibold)
                }
                PlayableContentGridView(items: Array(appleMusicBrowseService.usersRecentsAdded), limit: 6)
            }
            .listSectionSpacing(0)
            .listRowInsets(.default)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            
        case .recommendedAlbums:
            Section {
                NavigationLink(value: RouterDestination.playableGridScreen(title: "Recommended Albums", items: $appleMusicBrowseService.recommendedAlbums, action: { offset in
                    await appleMusicBrowseService.updateRecommendedAlbums(offset: offset)
                })) {
                    Text("Recommended Albums")
                        .fontDesign(.rounded)
                        .fontWeight(.semibold)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                
                if !appleMusicBrowseService.recommendedAlbums.isEmpty {
                    TileGrid(items: Array(appleMusicBrowseService.recommendedAlbums.prefix(TileGrid.fillCount)))
                }
            }
            .listSectionSpacing(0)
            .listRowInsets(.default)
        case .personalStations:
            Section {
                NavigationLink(value: RouterDestination.playableGridScreen(title: "Personal Stations", items: $appleMusicBrowseService.userStations, action: { offset in
                    await appleMusicBrowseService.updateRadioStations(offset: offset)
                })) {
                    Text("Personal Stations")
                        .fontDesign(.rounded)
                        .fontWeight(.semibold)
                }
                .listRowBackground(Color.clear)
                if !appleMusicBrowseService.userStations.isEmpty {
                    TileGrid(items: Array(appleMusicBrowseService.userStations.prefix(TileGrid.fillCount)))
                }
            }
            .listRowInsets(.default)
        }
    }
    
    private func updateAppleMusicBrowseService() async {
        isLoading = true
        await withTaskGroup { group in
            group.addTask {
                await appleMusicBrowseService.updateUsersApplePlaylistFolders(offset: 0)
            }
            
            group.addTask {
                await appleMusicBrowseService.updateUsersRecentPlayed(offset: 0, limit: 6)
            }
            
            group.addTask {
                await appleMusicBrowseService.updateUsersRecentAddedTracks(offset: 0, limit: 6)
            }
            
            group.addTask {
                await appleMusicBrowseService.updateRadioStations(offset: 0, limit: TileGrid.fillCount)
            }
            
            group.addTask {
                await appleMusicBrowseService.updateRecommendedAlbums(offset: 0, limit: TileGrid.fillCount)
            }
            // Albums, artists, songs and favorites read themselves when
            // opened.
        }
        isLoading = false
    }
}

#Preview {
    AppleLibraryBrowseScreen()
        .withEnvironments()
        .environment(SelectedGroupService(group: .theater))
}

