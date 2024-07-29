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

    @State private var coreFeatures = CoreFeatures()
    @State private var alertService = AlertService()
    @State private var searchCompletionTapped: Bool = false
    @State private var suggestion: String? = nil
    @State private var searchFieldIsPresented: Bool = true
    @State private var filters: [FilterSelection] = FilterSelection.defaultFilters

    var body: some View {
        @Bindable var router = router


        @Bindable var musicSearchService = musicSearchService
        NavigationStack(path: $router.path) {
            List {
                filterView
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

                if musicSearchService.query.isEmpty, contentToAdd == nil {
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
            .ignoresSafeArea(.keyboard)
            .contentMargins(.bottom, 80, for: .scrollContent)
            .searchable(
                text: $musicSearchService.query,
                isPresented: $searchFieldIsPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Searching \(musicSearchSelection.title)"
            )
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(contentToAdd == nil ? "Search" : "Adding to Alarm")
            .withAppRouter(router: router)
            .withSheetDestinations(sheetDestinations: $router.presentedSheet)
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
        }
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
        .onChange(of: router.dismiss) {
            dismiss()
        }
        .safeAreaInset(edge: .bottom) {
            if contentToAdd == nil {
                MiniPlayerView()
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
                FilterView(filters: $filters)
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
                        router.presentedSheet = .settings
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

