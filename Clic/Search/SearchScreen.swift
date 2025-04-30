import Analytics
import CloudStorage
import MusicSearchKit
import Defaults
import NukeUI
import UIKit
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit
import Defaults
import TipKit

struct SearchScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissSearch) private var dismissSearch
    
    @Environment(SonosService.self) private var sonosService: SonosService
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(Router.self) private var router: Router
    @Environment(PlaylistContainer.self) private var playlistsContainer
    @Environment(PlayHistoryService.self) private var playHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService
    @Environment(ContentToAdd.self) private var contentToAdd: ContentToAdd?

    @AppStorage(AppStorageKeys.mediaService) private var musicSearchSelection: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    var closeInspector: (() -> Void)? = nil

    var isAlarmSearch: Bool = false
    @State private var coreFeatures = CoreFeatures.shared
    @State private var alertService = AlertService.shared
    @State private var searchCompletionTapped: Bool = false
    @State private var suggestion: String? = nil
    @State private var searchFieldIsPresented: Bool = true
    @State private var filters: [FilterSelection] = FilterSelection.defaultFilters
    
    @FocusState private var isSearchFieldFocused: Bool
    
    @State private var isLoading: Bool = false
    
    private var showAlert: Bool {
#if targetEnvironment(macCatalyst)
        return false
#else
        return UIDevice.current.userInterfaceIdiom == .phone
#endif
    }

    var body: some View {
        @Bindable var router = router
        @Bindable var musicSearchService = musicSearchService
        @Bindable var sonosService = sonosService
        
        NavigationStack(path: $router.path) {
            List {
                filterView
//                if musicSearchSelection == .plex {
//                    LoggerView()
//                }
#if targetEnvironment(macCatalyst)
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
#endif

                if !playHistoryService.history.isEmpty, musicSearchService.query.isEmpty {
                    PlayHistoryView(filters: $filters)
                }
                
                if musicSearchService.query.isEmpty, !isAlarmSearch,  musicSearchSelection == .spotify {
                    SpotifyUsersPlaylistView()
                }

                if musicSearchService.query.isEmpty, !isAlarmSearch {
                    FavoritesView()
                }

                if !musicSearchService.query.isEmpty {
                    switch musicSearchSelection {
                    case .spotify:
                        SpotifySearchView(spotifyResults: musicSearchService.spotifyResults, filters: $filters)
                    case .apple:
                        AppleMusicSearchScreen(appleSearchResults: musicSearchService.appleResults, filters: $filters)
                    case .library:
                        LibrarySearchView(librarySearchResults: musicSearchService.librarySearchResults, filters: $filters)
                    case .plex:
                        PlexSearchView(query: $musicSearchService.query, plexResults: musicSearchService.plexResults, filters: $filters)
                    case .tidal:
                        TidalSearchView(tidalResults: musicSearchService.tidalResults, filters: $filters)
                    case .tuneIn:
                        TuneInSearchView(tuneInResults:  musicSearchService.tuneInResults, filters: $filters)
                    case .soundcloud:
                        ServiceSearchView(results: musicSearchService.searchResults, filters: $filters)
                    }
                }

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .listRowSeparator(.hidden)
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
            .searchFocusedBackport($isSearchFieldFocused)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(isAlarmSearch ? "Adding to Alarm" : "Search")
            .task(id: musicSearchService.query + musicSearchSelection.rawValue) {
                isLoading = true
                if suggestion == nil {
                    searchCompletionTapped = false
                }
                await musicSearchService.search(for: musicSearchSelection)
                suggestion = nil
                isLoading = false
                playlistsContainer.playlists = await sonosService.sonosPlaylists()
            }
            .animation(.snappy, value: playHistoryService.history)
            .animation(.snappy, value: musicSearchService.appleResults)
            .animation(.snappy, value: musicSearchService.spotifyResults)
            .animation(.snappy, value: musicSearchService.librarySearchResults)
            .animation(.snappy, value: musicSearchService.tidalResults)
            .animation(.snappy, value: musicSearchService.plexResults)
            .animation(.snappy, value: musicSearchService.searchResults)
            .animation(.snappy, value: filters)
            .animation(.snappy, value: searchCompletionTapped)
            .addDismiss(override: contentToAdd != nil) {
                dismiss()
                closeInspector?()
            }
            .withAppRouter()
        }
        .withAlert(enabled: showAlert)
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
        .overlay(alignment: .bottom) {
#if !targetEnvironment(macCatalyst)
            searchSuggestions
#endif
        }
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
        .animation(.interactiveSpring, value: MiniPlayerManger.shared.offset)
        .animation(.interactiveSpring, value: isSearchFieldFocused)
        .animation(.interactiveSpring, value: musicSearchService.suggestions)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
    }

    @MainActor
    private func showKeyboard() {
        UIView.setAnimationsEnabled(false)
        Task {
            try await Task.sleep(for: .milliseconds(300))
            UIView.setAnimationsEnabled(true)
        }
    }

    @MainActor
    private var filterView: some View {
        VStack(spacing: 0) {
            HStack {
                if musicSearchSelection != .tuneIn {
                    FilterView(selectedService: $musicSearchSelection, filters: $filters)
                }
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
    
    private var searchSuggestions: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(musicSearchService.suggestions) { suggestion in
                    Button {
                        musicSearchService.query = suggestion.searchTerm
                        self.suggestion = suggestion.searchTerm
                        searchCompletionTapped = true
                        hideKeyboard()
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text(suggestion.displayTerm)
                            Spacer()
                        }
                        .foregroundStyle(.accent)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                }
            }
            .padding(.vertical)
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .background(.regularMaterial)
        .opacity((isSearchFieldFocused && !musicSearchService.suggestions.isEmpty) ? 1 : 0)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .mask(
            HStack(spacing: 0) {
                LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0), Color.black]),
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 20)
                Rectangle().fill(Color.black)
                LinearGradient(gradient: Gradient(colors: [Color.black, Color.black.opacity(0)]),
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 20)
            }
            .padding(.leading, -15)
        )
        .scrollClipDisabled()
    }
}

#Preview {
    SearchScreen()
        .environment(SonosService.shared)
}
