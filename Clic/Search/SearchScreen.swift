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

    @AppStorage(AppStorageKeys.mediaService) private var musicSearchSelection: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    @State private var alertService = AlertService()
    @State private var searchCompletionTapped: Bool = false
    @State private var suggestion: String? = nil
    @State private var searchFieldIsPresented: Bool = true
    @State private var filters: [FilterSelection] = FilterSelection.defaultFilters

    @CloudStorage(CloudKeys.playHistory) private var playHistory: OrderedSet<PlayableContent> = [] {
        didSet {
            playHistory = OrderedSet(playHistory.prefix(15))
        }
    }

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

                        if !playHistory.isEmpty, musicSearchService.query.isEmpty {
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
                                ForEach(musicSearchService.topResults) { result in
                                    AppleMusicSearchScreen(result: result, filters: $filters, group: group)
                                        .fontDesign(.rounded)
                                }
                            case .library:
                                LibrarySearchView(librarySearchResults: musicSearchService.librarySearchResults, filters: $filters, group: group)
                            case .plex:
                                PlexSearchView(plexResults: musicSearchService.plexResults, filters: $filters, group: group)
                            case .tidal:
                                TidalSearchView(tidalResults: musicSearchService.tidalResults, filters: $filters, group: group)
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
                    }
                    .animation(.interactiveSpring, value: musicSearchService.topResults)
                    .animation(.interactiveSpring, value: searchCompletionTapped)
                    .overlay(alignment: .bottom) {
                        HStack {
                            FilterView(filters: $filters)
                            Spacer()
                            Menu {
                                Button {
                                    HapticManager.shared.fireHaptic(.buttonPress)
                                    musicSearchSelection = .spotify
                                    Analytics.shared.track(.selectedMusicService, with: ["MusicService": musicSearchSelection.rawValue])
                                    Analytics.shared.setSelection(metadata: ["MusicService": musicSearchSelection.rawValue])
                                } label: {
                                    HStack {
                                        Text("Spotify")
                                        Image(.spotifyLogo)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .tag(MediaSearchService.spotify)
                                            .frame(width: 24, height: 24)
                                    }
                                }
                                .id(MediaSearchService.spotify)

                                Button {
                                    HapticManager.shared.fireHaptic(.buttonPress)
                                    musicSearchSelection = .apple
                                    Analytics.shared.track(.selectedMusicService, with: ["MusicService": musicSearchSelection.rawValue])
                                    Analytics.shared.setSelection(metadata: ["MusicService": musicSearchSelection.rawValue])
                                } label: {
                                    HStack {
                                        Text("Apple Music")
                                        Image(systemName: "apple.logo")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 24, height: 24)
                                    }
                                }
                                .id(MediaSearchService.apple)

                                Button {
                                    HapticManager.shared.fireHaptic(.buttonPress)
                                    musicSearchSelection = .library
                                    Analytics.shared.track(.selectedMusicService, with: ["MusicService": musicSearchSelection.rawValue])
                                    Analytics.shared.setSelection(metadata: ["MusicService": musicSearchSelection.rawValue])
                                } label: {
                                    Label("Library", systemImage: "books.vertical.fill")
                                }
                                .id(MediaSearchService.library)

                                // MARK: Hide feature until later
                                //                                Button {
                                //                                    HapticManager.shared.fireHaptic(.buttonPress)
                                //                                    musicSearchSelection = .plex
                                //                                    Analytics.shared.track(.selectedMusicService, with: ["MusicService": musicSearchSelection.rawValue])
                                //                                    Analytics.shared.setSelection(metadata: ["MusicService": musicSearchSelection.rawValue])
                                //                                } label: {
                                //                                    HStack {
                                //                                        Text(MediaSearchService.plex.title)
                                //                                        Image(.plex)
                                //                                            .resizable()
                                //                                            .aspectRatio(contentMode: .fit)
                                //                                            .frame(width: 24, height: 24)
                                //                                            .clipShape(Circle())
                                //                                    }
                                //                                }
                                //                                .id(MediaSearchService.plex)

                                // MARK: Hide feature until later

                                //                                Button {
                                //                                    HapticManager.shared.fireHaptic(.buttonPress)
                                //                                    musicSearchSelection = .tidal
                                //                                    Analytics.shared.track(.selectedMusicService, with: ["MusicService": musicSearchSelection.rawValue])
                                //                                    Analytics.shared.setSelection(metadata: ["MusicService": musicSearchSelection.rawValue])
                                //                                } label: {
                                //                                    HStack {
                                //                                        Text(MediaSearchService.tidal.title)
                                //                                        MediaSearchService.tidal.icon
                                //                                            .resizable()
                                //                                            .aspectRatio(contentMode: .fit)
                                //                                            .frame(width: 24, height: 24)
                                //                                            .clipShape(Circle())
                                //                                    }
                                //                                }
                                //                                .id(MediaSearchService.tidal)
                            } label: {
                                Label {
                                    Text(musicSearchSelection.title)
                                } icon: {
                                    iconForMusicService
                                }
                                .labelStyle(.iconOnly)
                            }
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
            Image(.spotifyLogo)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        case .apple:
            Image(systemName: "apple.logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        case .library:
            Image(systemName: "books.vertical.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        case .plex:
            Image(.plex)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .clipShape(Circle())
        case .tidal:
            musicSearchSelection.icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        }
    }
}

#Preview {
    SearchScreen(group: nil)
        .environment(SonosService.shared)
}

