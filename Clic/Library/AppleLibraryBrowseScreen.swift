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
import TipKit

struct AppleLibraryBrowseScreen: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(AppleMusicBrowseService.self) private var appleMusicBrowseService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService
    @Environment(\.dismiss) var dismiss
    
    @State private var router = Router()
    @State private var isLoading = true
    
    private var numberOfItemsInGrid: Int {
        return 6
    }
    
    var body: some View {
        @Bindable var appleMusicBrowseService = appleMusicBrowseService
        @Bindable var sonosService = sonosService
        
        NavigationStack(path: $router.path) {
            List {
                NavigationLink(value: RouterDestination.playableLibraryList(title: "Artists", items: $appleMusicBrowseService.userArtists, action: { offset in
                    await appleMusicBrowseService.updateUsersAppleArtists(offset: offset)
                })) {
                    Label("Artists", systemImage: "music.mic")
                        .foregroundStyle(.primary)
                }
                
                NavigationLink(value: RouterDestination.playableLibraryList(title: "Albums", items: $appleMusicBrowseService.userAlbums, action: { offset in
                    await appleMusicBrowseService.updateUsersAppleAlbums()
                })) {
                    Label("Albums", systemImage: "smallcircle.circle.fill")
                }
                
                NavigationLink(value: RouterDestination.playableLibraryList(title: "Songs", items: $appleMusicBrowseService.userSongs, action: { offset in
                    await appleMusicBrowseService.updateUsersAppleSongs()
                })) {
                    Label("Songs", systemImage: "music.note")
                }
                
                Section {
                    if !appleMusicBrowseService.userPlaylists.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {
                            ForEach(appleMusicBrowseService.userPlaylists.prefix(numberOfItemsInGrid)) { item in
                                PlayableCardView(item: item)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    NavigationLink(value: RouterDestination.playableGridScreen(title: "Playlists", items: $appleMusicBrowseService.userPlaylists, action: { offset in
                        await appleMusicBrowseService.updateUsersApplePlaylists()
                    })) {
                        HStack {
                            Text("Playlists")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .headerProminence(.increased)
                
                
                Section {
                    if !appleMusicBrowseService.usersRecents.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {
                            ForEach(appleMusicBrowseService.usersRecents.prefix(numberOfItemsInGrid)) { item in
                                PlayableCardView(item: item)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    NavigationLink(value: RouterDestination.playableGridScreen(title: "Recently Played", items: $appleMusicBrowseService.usersRecents, action: { offset in
                        await appleMusicBrowseService.updateUsersRecentPlayed(offset: offset)
                    })) {
                        HStack {
                            Text("Recently Played")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .headerProminence(.increased)
             
                
                Section {
                    if !appleMusicBrowseService.usersRecentsAdded.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {                        ForEach(appleMusicBrowseService.usersRecentsAdded.prefix(numberOfItemsInGrid)) { item in
                                PlayableCardView(item: item)
                                    .buttonStyle(.plain)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    NavigationLink(value: RouterDestination.playableGridScreen(title: "Recently Added", items: $appleMusicBrowseService.usersRecentsAdded, action: { offset in
                        await appleMusicBrowseService.updateUsersRecentAddedTracks(offset: offset)
                    })) {
                        HStack {
                            Text("Recently Added")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .headerProminence(.increased)
                
                Section {
                       if !appleMusicBrowseService.userStations.isEmpty {
                           LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {
                               ForEach(appleMusicBrowseService.userStations.prefix(numberOfItemsInGrid)) { item in
                                   PlayableCardView(item: item)
                               }
                           }
                           .listRowBackground(Color.clear)
                       }
                } header: {
                    NavigationLink(value: RouterDestination.playableGridScreen(title: "Personal Stations", items: $appleMusicBrowseService.userStations, action: { offset in
                        await appleMusicBrowseService.updateRadioStations(offset: offset)
                    })) {
                        HStack {
                            Text("Personal Stations")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .headerProminence(.increased)
                
            }
            .miniPlayerOnScrollHandler()
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
    
    @MainActor
    private func updateAppleMusicBrowseService() async {
        isLoading = true
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await appleMusicBrowseService.updateUsersApplePlaylists()
            }
            group.addTask {
                await appleMusicBrowseService.updateUsersRecentPlayed()
            }
            group.addTask {
                await appleMusicBrowseService.updateUsersRecentAddedTracks()
            }
            group.addTask {
                await appleMusicBrowseService.updateUsersAppleAlbums()
            }
            group.addTask {
                await appleMusicBrowseService.updateUsersAppleArtists()
            }
            group.addTask {
                await appleMusicBrowseService.updateRadioStations()
            }
        }
        isLoading = false
    }
}

#Preview {
    BrowseScreen()
        .withEnvironments()
}

