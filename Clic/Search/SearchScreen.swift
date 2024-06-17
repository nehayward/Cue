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
    @Environment(SonosService.self) private var sonosService: SonosService
    @Environment(\.dismiss) private var dismiss
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(ContentToAdd.self) private var contentToAdd: ContentToAdd?
    @Environment(Router.self) private var router: Router
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService

    @AppStorage(AppStorageKeys.mediaService) private var musicSearchSelection: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    @State private var betaFeatures = BetaFeatures()
    @State private var coreFeatures = CoreFeatures()
    @State private var alertService = AlertService()
    @State private var searchCompletionTapped: Bool = false
    @State private var suggestion: String? = nil
    @State private var searchFieldIsPresented: Bool = true
    @State private var filters: [FilterSelection] = FilterSelection.defaultFilters

    var group: GroupRoom?

    var body: some View {
        @Bindable var router = router

        Group {
            switch appleMusicAuthorized {
            case .authorized:
                @Bindable var musicSearchService = musicSearchService
                NavigationStack(path: $router.path) {
                    List {
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

                        // MARK: Hide Favorites for until programURI is added
                        if musicSearchService.query.isEmpty, contentToAdd == nil {
                            FavoritesView()
                        }

                        if !musicSearchService.query.isEmpty {
                            switch musicSearchSelection {
                            case .spotify:
                                SpotifySearchView(spotifyResults: $musicSearchService.spotifyResults, filters: $filters, group: group)
                            case .apple:
                                AppleMusicSearchScreen(appleSearchResults: musicSearchService.appleResults, filters: $filters, group: group)
                            case .library:
                                LibrarySearchView(librarySearchResults: musicSearchService.librarySearchResults, filters: $filters, group: group)
                            case .plex:
                                PlexSearchView(plexResults: musicSearchService.plexResults, filters: $filters, group: group)
                            case .tidal:
                                TidalSearchView(tidalResults: musicSearchService.tidalResults, filters: $filters, group: group)
                            case .tuneIn:
                                TuneInSearchView(tuneInResults:  musicSearchService.tuneInResults, filters: $filters, group: group)
                            }
                        }
                    }
                    .ignoresSafeArea(.keyboard)
                    .contentMargins(.bottom, 100, for: .scrollContent)
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
                    .animation(.bouncy, value: playHistoryService.history)
                    .animation(.bouncy, value: musicSearchService.appleResults)
                    .animation(.bouncy, value: musicSearchService.spotifyResults)
                    .animation(.bouncy, value: musicSearchService.librarySearchResults)
                    .animation(.bouncy, value: musicSearchService.tidalResults)
                    .animation(.bouncy, value: musicSearchService.plexResults)
                    .animation(.bouncy, value: filters)
                    .animation(.interactiveSpring, value: searchCompletionTapped)
                    .overlay(alignment: .bottom) {
                        HStack {
                            FilterView(filters: $filters)
                            Spacer()
                            Menu {
                                ForEach(MediaSearchService.allCases, id: \.self) { service in
                                    if ![MediaSearchService.plex].contains(service) {
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
                                    iconForMusicService
                                }
                                .labelStyle(.iconOnly)
                            }
                            .popoverTip(AppTip.mediaService)
                        }
                        .padding([.vertical, .trailing])
                        .background {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .ignoresSafeArea(.container, edges: .bottom)
                        }
                    }
                }
                .keyboardType(.asciiCapable)
                .autocorrectionDisabled()
#if !os(visionOS)
                .scrollDismissesKeyboard(.immediately)
#endif
                .presentationDragIndicator(.hidden)
                .scrollContentBackground(.hidden)
                .listStyle(.inset)
                //                .listStyle(.grouped) // MARK: Update later.
                //                .headerProminence(.increased)
                .environment(router)
                .environment(group)
                .environment(musicSearchService)
                .environment(alertService)
                .onChange(of: router.dismiss) {
                    dismiss()
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            case .notDetermined, .denied:
                AppleMusicPermissionsView()
                    .environment(musicSearchService)
                    .addDismiss(action: dismiss.callAsFunction)
            }
        }
        .onAppear {
            searchFieldIsPresented = true
            musicSearchService.query = ""

            if musicSearchService.query.isEmpty {
                appleMusicAuthorized = musicSearchService.getMusicAuthorization()
                Task {
                    await sonosService.getFavoriteList()
                }
            }
            if UIDevice.current.userInterfaceIdiom == .phone {
                showKeyboard()
            }
        }
        .safeAreaInset(edge: .top) {
            if alertService.alert.isShowing {
                PillView()
                    .environment(alertService)
            }
        }
        .animation(.spring, value: alertService.alert.isShowing)
//        .overlay(alignment: .bottom) {
//            if !searchFieldIsPresented {
//                MiniPlayerView(groupID: group?.coordinatorID)
//                    .ignoresSafeArea(.keyboard, edges: .bottom)
//            }
//        }
    }

    @MainActor
    private func showKeyboard() {
        UIView.setAnimationsEnabled(false)
        Task {
            try await Task.sleep(for: .milliseconds(400))
            UIView.setAnimationsEnabled(true)
        }
    }

    @ViewBuilder
    private var iconForMusicService: some View {
        switch musicSearchSelection {
        case .spotify:
            MusicService.spotify.image
                .foregroundStyle(.thinMaterial)
                .frame(width: 24, height: 24)
        case .apple:
            Image(systemName: "apple.logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.foreground)
                .frame(width: 24, height: 24)
        case .library:
            Image(systemName: "books.vertical.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.foreground)
                .frame(width: 24, height: 24)
        case .plex:
            MusicService.plex.image
                .foregroundStyle(.orange.gradient)
                .frame(width: 24, height: 24)
        case .tidal:
            MusicService.tidal.image
                .frame(width: 24, height: 24)
        case .tuneIn:
            MediaSearchService.tuneIn.image
                .frame(width: 24, height: 24)

        }
    }
}

#Preview {
    SearchScreen(group: nil)
        .environment(SonosService.shared)
}

