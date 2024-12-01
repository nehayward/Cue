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

struct SpotifyPlaylistScreen: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(SpotifyBrowseService.self) private var spotifyBrowseService: SpotifyBrowseService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var router = Router()
    @State private var isLoading = true
    @State private var query: String = ""
    @State private var isSearching: Bool = false
    @State private var showChangeUserConfirmation: Bool = false

    @AppStorage("spotify.userID.clic") private var userID: String = ""
    
    var body: some View {
        @Bindable var appleMusicBrowseService = spotifyBrowseService
        @Bindable var sonosService = sonosService
        
        NavigationStack(path: $router.path) {
            List {
                if userID.isEmpty {
                    Group {
                        if let user = spotifyBrowseService.foundUser {
                            Button {
                                spotifyBrowseService.userPlaylists.removeAll()
                                isSearching = false
                                query = ""
                                userID = user.id
                                spotifyBrowseService.foundUser = nil
                            } label: {
                                VStack(alignment: .center) {
                                    Spacer()
                                    LazyImage(url: user.images.biggestImageURL) { state in
                                        if let image = state.image {
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .transition(.opacity)
                                        } else {
                                            Circle()
                                                .foregroundStyle(.secondary)
                                                .transition(.opacity)
                                                .overlay {
                                                    Image(systemName: "person.fill")
                                                        .resizable()
                                                        .font(.title3)
                                                        .frame(maxWidth: 100, maxHeight: 100)
                                                        .padding()
                                                }
                                                .padding()
                                        }
                                    }
                                    .clipShape(Circle())
                                    .frame(maxWidth: .infinity, maxHeight: 200)
                                    Text(user.displayName ?? user.id)
                                        .font(.title)
                                        .padding(.bottom)
                                }
                            }
                            .buttonStyle(.bordered)
                        } else if !query.isEmpty, spotifyBrowseService.foundUser == nil {
                            Text("User Not found")
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                                .font(.title)
                                .padding()
                        } else {
                            ContentUnavailableView {
                                Text("Enter Spotify Username")
                                    .padding(.bottom)
                            } description: {
                                Text("Copy your username from your Spotify profile")
                            } actions: {
                                Link("Open Spotify Profile", destination: URL(string: "spotify://user")!)
                                    .underline()
                            }
                        }
                    }
                    .task(id: query) {
                        guard !query.isEmpty else {
                            spotifyBrowseService.foundUser = nil
                            return
                        }
                        await spotifyBrowseService.lookup(userID: query)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .onAppear {
                        isSearching = true
                    }
                    
                } else {
                    Group {
                        if !spotifyBrowseService.userPlaylists.isEmpty {
                            let filteredPlaylists = appleMusicBrowseService.userPlaylists.filter {
                                query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                            }
                            ForEach(filteredPlaylists) { item in
                                PlayableContentView(item: item)
                            }
                        }
                    }
                }
            }
            .miniPlayerOnScrollHandler()
            .listStyle(.plain)
            .searchable(text: $query, isPresented: $isSearching)  // Bind search query to the searchable modifier
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle(userID.isEmpty ? "Enter Spotify Username" : "\(userID) Playlists")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: userID) {
                await updateSpotifyBrowseService()
            }
            .toolbar {
                if !userID.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showChangeUserConfirmation = true
                        } label: {
                            Image(systemName: "person.fill")
                        }
                    }
                }
            }
            .refreshable {
                if !userID.isEmpty {
                    await updateSpotifyBrowseService()
                }
            }
            // MARK: Workaround into I can use extension on view iOS 18 bug
            .navigationDestination(for: RouterDestination.self) { destination in
                switch destination {
                case let .player(groupID):
                    if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }) {
                        LargePlayerView(group: $sonosService.sorted[group])
                    } else {
                        GroupNoLongerAvailableScreen()
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
                case .servicePreferenceScreen:
                    ServicePreferenceScreen()
                }
            }
        }
        .overlay {
            if isLoading, spotifyBrowseService.userPlaylists.isEmpty {
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
        .confirmationDialog("Change User", isPresented: $showChangeUserConfirmation) {
            Button {
                isSearching = true
                query = ""
                userID = ""
                spotifyBrowseService.foundUser = nil
            } label: {
                Text("Change User")
            }
        }
        .onDisappear {
            isSearching = false
            query = ""
            spotifyBrowseService.foundUser = nil
        }
    }
    
    @MainActor
    private func updateSpotifyBrowseService() async {
        isLoading = true
        defer { isLoading = false }
        if userID.isEmpty { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await spotifyBrowseService.updateUsersRecentPlayed(userID: userID)
            }
        }
    }
}

#Preview {
    BrowseScreen()
        .withEnvironments()
}
