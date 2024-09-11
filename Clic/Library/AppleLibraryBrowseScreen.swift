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
#if targetEnvironment(macCatalyst)
        return 2
#endif
        return 4
    }
    
    var body: some View {
        @Bindable var appleMusicBrowseService = appleMusicBrowseService
        @Bindable var sonosService = sonosService
        
        NavigationStack(path: $router.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NavigationLink(value: RouterDestination.playableLibraryList(title: "Artists", items: $appleMusicBrowseService.userArtists, action: { offset in
                        await appleMusicBrowseService.updateUsersAppleArtists(offset: offset)
                    })) {
                        HStack {
                            Label("Artists", systemImage: "music.mic")
                                .foregroundStyle(.primary)
                            Spacer()
                            
                            Text("Show all \(Image(systemName: "chevron.right"))")
                        }
                    }
                    .foregroundStyle(.secondary)
                    
                    NavigationLink(value: RouterDestination.playableLibraryList(title: "Albums", items: $appleMusicBrowseService.userAlbums, action: { offset in
                        await appleMusicBrowseService.updateUsersAppleAlbums()
                    })) {
                        HStack {
                            Label("Albums", systemImage: "smallcircle.circle.fill")
                            Spacer()
                            Text("Show all \(Image(systemName: "chevron.right"))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Section {
                        if !appleMusicBrowseService.userPlaylists.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                                ForEach(appleMusicBrowseService.userPlaylists.prefix(numberOfItemsInGrid)) { item in
                                    PlayableCardView(item: item)
                                }
                            }
                        }
                    } header: {
                        NavigationLink(value: RouterDestination.playableGridScreen(title: "Playlists", items: $appleMusicBrowseService.userPlaylists, action: { offset in
                            await appleMusicBrowseService.updateUsersApplePlaylists()
                        })) {
                            HStack {
                                Text("Playlists")
                                Spacer()
                                Text("Show all \(Image(systemName: "chevron.right"))")
                            }
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical)
                    }
                    
                    
                    NavigationLink(value: RouterDestination.playableGridScreen(title: "Recently Played", items: $appleMusicBrowseService.usersRecents, action: { offset in
                        await appleMusicBrowseService.updateUsersRecentPlayed(offset: offset)
                    })) {
                        HStack {
                            Text("Recently Played")
                            Spacer()
                            Text("Show all \(Image(systemName: "chevron.right"))")
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical)
                    
                    if !appleMusicBrowseService.usersRecents.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                            ForEach(appleMusicBrowseService.usersRecents.prefix(numberOfItemsInGrid)) { item in
                                PlayableCardView(item: item)
                            }
                        }
                    }
                    
                    NavigationLink(value: RouterDestination.playableGridScreen(title: "Recently Added", items: $appleMusicBrowseService.usersRecentsAdded, action: { offset in
                        await appleMusicBrowseService.updateUsersRecentAddedTracks(offset: offset)
                    })) {
                        HStack {
                            Text("Recently Added")
                            Spacer()
                            Text("Show all \(Image(systemName: "chevron.right"))")
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical)
                    
                    if !appleMusicBrowseService.usersRecentsAdded.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                            ForEach(appleMusicBrowseService.usersRecentsAdded.prefix(numberOfItemsInGrid)) { item in
                                PlayableCardView(item: item)
                            }
                        }
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("Apple Library")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await updateAppleMusicBrowseService()
            }
            // MARK: Workaround into I can use extension on view iOS 18 bug
            .navigationDestination(for: RouterDestination.self) { destination in
                switch destination {
                case let .player(groupID):
                    if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }) {
                        LargePlayerView(group: $sonosService.sorted[group])
                    } else {
                        Text("Group No Longer Available")
                            .onTapGesture {
                                dismiss()
                            }
                    }
                case let .groupDestination(content, position):
                    PlayerSelectionView(playableContent: content, position: position)
                case .manageScenes:
                    ManageSceneScreen()
                case let .mediaDetail(content, _):
                    MediaDetailView(playableContent: content)
                case let .artistDetail(content, _):
                    ArtistDetailView(playableContent: content)
                case .createScene:
                    SceneBuilderScreen()
                case .alarms:
                    AlarmListView()
                case let .addAlarm(group):
                    AlarmView(group: group, alarm: .newAlarm)
                case let .editAlarm(alarm):
                    AlarmView(edit: true, alarm: alarm)
                case .speakerSettingsList:
                    SpeakerSettingsListView()
                case let .speakerSettings(room: room):
                    SpeakerSettingsView(room: room)
                case let .playableContentList(group: group, contentType: contentType):
                    let title = switch contentType {
                    case .track:
                        "Songs"
                    case .album:
                        "Albums"
                    case .artist:
                        "Artists"
                    case .playlist:
                        "Playlists"
                    default:
                        ""
                    }
                    PlayableContentList(type: contentType)
                        .navigationTitle(title)
                        .environment(group)
                case .fullPlayHistoryList:
                    PlayHistoryFullView()
                case let .playableLibraryList(title: title, items: items, action: action):
                    PlayableList(items: items, action: action)
                        .navigationTitle(title)
                case let .playableGridScreen(title: title, items: items, action: action):
                    PlayableGridScreen(items: items, action: action)
                        .navigationTitle(title)
                case .houseHold:
                    HouseholdScreen()
                }
            }
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
        await appleMusicBrowseService.updateUsersApplePlaylists()
        await appleMusicBrowseService.updateUsersRecentPlayed()
        await appleMusicBrowseService.updateUsersRecentAddedTracks()
        await appleMusicBrowseService.updateUsersAppleAlbums()
        await appleMusicBrowseService.updateUsersAppleArtists()
        isLoading = false
    }
}

#Preview {
    BrowseScreen()
        .withEnvironments()
}

