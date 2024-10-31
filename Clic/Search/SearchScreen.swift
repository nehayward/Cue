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

struct SearchScreen: View {
    @Environment(\.dismiss) private var dismiss
    
    @Environment(SonosService.self) private var sonosService: SonosService
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(Router.self) private var router: Router
    @Environment(PlaylistContainer.self) private var playlistsContainer
    @Environment(PlayHistoryService.self) private var playHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService
    @Environment(ContentToAdd.self) private var contentToAdd: ContentToAdd?

    @AppStorage(AppStorageKeys.mediaService) private var musicSearchSelection: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    var closeInspector: (() -> Void)? = nil

    var isAlarmSearch: Bool = false
    @State private var coreFeatures = CoreFeatures.shared
    @State private var alertService = AlertService()
    @State private var searchCompletionTapped: Bool = false
    @State private var suggestion: String? = nil
    @State private var searchFieldIsPresented: Bool = true
    @State private var filters: [FilterSelection] = FilterSelection.defaultFilters

    var body: some View {
        @Bindable var router = router
        @Bindable var musicSearchService = musicSearchService
        @Bindable var sonosService = sonosService
        
        NavigationStack(path: $router.path) {
            List {
                filterView
//                LoggerView()
                if !searchCompletionTapped {
                    ForEach(musicSearchService.suggestions) { suggestion in
                        Button {
                            musicSearchService.query = suggestion.searchTerm
                            self.suggestion = suggestion.searchTerm
                            searchCompletionTapped = true
                        } label: {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                Text(suggestion.displayTerm)
                                Spacer()
                            }
                            .foregroundStyle(.accent)
                        }
                    }
                }

                if !playHistoryService.history.isEmpty, musicSearchService.query.isEmpty {
                    PlayHistoryView(filters: $filters)
                }

                if musicSearchService.query.isEmpty, !isAlarmSearch {
                    FavoritesView()
                }

                if !musicSearchService.query.isEmpty {
                    switch musicSearchSelection {
                    case .spotify:
                        SpotifySearchView(spotifyResults: $musicSearchService.spotifyResults, filters: $filters)
                    case .apple:
                        AppleMusicSearchScreen(appleSearchResults: musicSearchService.appleResults, filters: $filters)
                    case .library:
                        LibrarySearchView(librarySearchResults: musicSearchService.librarySearchResults, filters: $filters)
                    case .plex:
                        PlexSearchView(plexResults: musicSearchService.plexResults, filters: $filters)
                    case .tidal:
                        TidalSearchView(tidalResults: musicSearchService.tidalResults, filters: $filters)
                    case .tuneIn:
                        TuneInSearchView(tuneInResults:  musicSearchService.tuneInResults, filters: $filters)
                    }
                }
            }
            .miniPlayerOnScrollHandler()
            .ignoresSafeArea(.keyboard)
            .contentMargins(.bottom, 120, for: .scrollContent)
            .searchable(
                text: $musicSearchService.query,
                isPresented: $searchFieldIsPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Searching \(musicSearchSelection.title)"
            )
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(isAlarmSearch ? "Adding to Alarm" : "Search")
            .task(id: musicSearchService.query + musicSearchSelection.rawValue) {
                if suggestion == nil {
                    searchCompletionTapped = false
                }
                await musicSearchService.search(for: musicSearchSelection)
                suggestion = nil

                playlistsContainer.playlists = await sonosService.sonosPlaylists()
            }
            // MARK: Bring back
            .animation(.bouncy, value: playHistoryService.history)
            .animation(.bouncy, value: musicSearchService.appleResults)
            .animation(.bouncy, value: musicSearchService.spotifyResults)
            .animation(.bouncy, value: musicSearchService.librarySearchResults)
            .animation(.bouncy, value: musicSearchService.tidalResults)
            .animation(.bouncy, value: musicSearchService.plexResults)
            .animation(.bouncy, value: filters)
            .animation(.interactiveSpring, value: searchCompletionTapped)
            .addDismiss(override: contentToAdd != nil) {
                dismiss()
                closeInspector?()
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
                case .servicePreferenceScreen:
                    ServicePreferenceScreen()
                }
            }
        }
        .withAlert()
        .animation(.spring, value: alertService.alert.isShowing)
        .keyboardType(.asciiCapable)
        .autocorrectionDisabled()
#if !os(visionOS)
        .scrollDismissesKeyboard(.immediately)
#endif
        .presentationDragIndicator(.hidden)
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
        .foregroundStyle(.primary)
        .environment(router)
        .environment(musicSearchService)
        .environment(alertService)
        .onChange(of: contentToAdd?.content) {
            dismiss()
        }
        .safeAreaInset(edge: .bottom) {
            if contentToAdd == nil {
                MiniPlayerView()
                    .offset(y: MiniPlayerManger.shared.offset)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            searchFieldIsPresented = true
            musicSearchService.query = ""

            if musicSearchService.query.isEmpty {
                Task {
                    await sonosService.getFavoriteList()
                }
            }
            if UIDevice.current.userInterfaceIdiom == .phone {
                showKeyboard()
            }
        }
        .environment(selectedGroupService)
        .animation(.interactiveSpring, value: MiniPlayerManger.shared.offset)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
    }

    @MainActor
    private func showKeyboard() {
        UIView.setAnimationsEnabled(false)
        Task {
            try await Task.sleep(for: .milliseconds(400))
            UIView.setAnimationsEnabled(true)
        }
    }

    @MainActor
    private var filterView: some View {
        VStack(spacing: 0) {
            HStack {
                FilterView(selectedService: $musicSearchSelection, filters: $filters)
                Spacer()
                Menu {
                    ForEach(MediaSearchService.allCases, id: \.self) { service in
                        if coreFeatures.enabledServices(service).wrappedValue {
                            Button {
                                HapticManager.shared.fireHaptic(.buttonPress)
                                musicSearchSelection = service
                                Analytics.shared.track(.selectedMusicService, with: ["MusicService": service.rawValue])
                                Analytics.shared.setSelection(metadata: ["MusicService": service.rawValue])

                                if service == .tuneIn {
                                    for filter in filters {
                                        filter.isFiltered = false
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(service.title)
                                    service.image
                                        .tag(service)
                                        .frame(width: 24, height: 24)
                                }
                            }
                            .id(service)
                        }
                    }
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        router.presentedSheet = .settings(destination: .servicePreferenceScreen)
                    } label: {
                        Text("Customize in Settings…")
                    }
                } label: {
                    Label {
                        Text(musicSearchSelection.title)
                    } icon: {
                        musicSearchSelection
                            .iconForMusicService
                            .frame(width: 24, height: 24)
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
                }
                .popoverTip(AppTip.mediaService)
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

#Preview {
    SearchScreen()
        .environment(SonosService.shared)
}
