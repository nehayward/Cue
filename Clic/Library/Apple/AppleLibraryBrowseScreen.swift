import Analytics
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
                ForEach(configStore.configuration.visibleSections(), id: \.self) { section in
                    sectionView(for: section)
                }
            }
#if targetEnvironment(macCatalyst)
            .listStyle(.plain)
#endif
            .contentMargins(.top, EdgeInsets(), for: .scrollContent)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("Apple Library")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await updateAppleMusicBrowseService()
            }
            .withAppRouter()
            .toolbar {
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
        .overlay {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
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
            NavigationLink(value: RouterDestination.playableLibraryList(title: "Artists", items: $appleMusicBrowseService.userArtists, action: { offset in
                await appleMusicBrowseService.updateUsersAppleArtists(offset: offset)
            })) {
                Label("Artists", systemImage: "music.mic")
                    .foregroundStyle(.primary)
            }
        case .albums:
            NavigationLink(value: RouterDestination.playableLibraryList(title: "Albums", items: $appleMusicBrowseService.userAlbums, action: { offset in
                await appleMusicBrowseService.updateUsersAppleAlbums()
            })) {
                Label("Albums", systemImage: "smallcircle.circle.fill")
            }
            
        case .songs:
            NavigationLink(value: RouterDestination.playableLibraryList(title: "Songs", items: $appleMusicBrowseService.userSongs, action: { offset in
                await appleMusicBrowseService.updateUsersAppleSongs()
            })) {
                Label("Songs", systemImage: "music.note")
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
                .tag(UUID().uuidString)
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
                    HStack(spacing: 12) {
                        ForEach(appleMusicBrowseService.recommendedAlbums.prefix(2)) { item in
                            PlayableCardView(item: item)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
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
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            ForEach(appleMusicBrowseService.userStations.prefix(3)) { item in
                                PlayableCardView(item: item)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
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
                await appleMusicBrowseService.updateRadioStations(offset: 0, limit: 4)
            }
            
            group.addTask {
                await appleMusicBrowseService.updateRecommendedAlbums(offset: 0, limit: 4)
            }
            
            group.addTask {
                await appleMusicBrowseService.updateUsersAppleAlbums()
            }
            
            group.addTask {
                await appleMusicBrowseService.updateUsersAppleArtists()
            }
            
        }
        isLoading = false
    }
}

#Preview {
    AppleLibraryBrowseScreen()
        .withEnvironments()
        .environment(SelectedGroupService(group: .theater))
}

