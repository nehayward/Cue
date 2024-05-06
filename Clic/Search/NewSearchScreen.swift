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

struct NewSearchScreen: View {
    @Environment(SonosService.self) private var sonosService: SonosService
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) var parentRouter: Router?
    @Environment(MusicSearchService.self) var musicSearchService

    @AppStorage(AppStorageKeys.mediaService) private var musicSearchSelection: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    @State private var router: Router = Router()
    @State private var isKeyboardVisible = false
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
    var instant: Bool = false

    var body: some View {
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

                        if musicSearchService.query.isEmpty, musicSearchSelection == .spotify {
                            NewReleasesView()
                        }

                        if !playHistory.isEmpty, musicSearchService.query.isEmpty {
                            PlayHistoryView(filters: $filters)
                        }

                        if musicSearchService.query.isEmpty {
                            FavoritesView()
                        }

                        if !musicSearchService.query.isEmpty {
                            switch musicSearchSelection {
                            case .spotify:
                                SpotifySearchView(isAdding: false, addingContent: .constant(nil), spotifyResult: $musicSearchService.spotifyResult, filters: $filters, group: group)
                            case .apple:
                                ForEach(musicSearchService.topResults) { result in
                                    AppleMusicSearchScreen(result: result, filters: $filters, group: group)
                                        .fontDesign(.rounded)
                                }
                            case .library:
                                LibrarySearchView(librarySearchResults: musicSearchService.librarySearchResults, filters: $filters, group: group)
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
                    .navigationTitle("Search")
                    .withAppRouter(router: router)
                    .withSheetDestinations(sheetDestinations: $router.presentedSheet)
                    .task(id: musicSearchService.query + musicSearchSelection.rawValue) {
                        if suggestion == nil {
                            searchCompletionTapped = false
                        }
//                        if appleMusicAuthorized == .notDetermined { return }
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
                                            .tag(SearchSelection.spotify)
                                            .frame(width: 24, height: 24)
                                    }
                                }
                                .id(SearchSelection.spotify)
                                
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
                                            .tag(SearchSelection.spotify)
                                            .frame(width: 24, height: 24)
                                    }
                                }
                                .id(SearchSelection.apple)

                                Button {
                                    HapticManager.shared.fireHaptic(.buttonPress)
                                    musicSearchSelection = .library
                                    Analytics.shared.track(.selectedMusicService, with: ["MusicService": musicSearchSelection.rawValue])
                                    Analytics.shared.setSelection(metadata: ["MusicService": musicSearchSelection.rawValue])
                                } label: {
                                    Label("Library", systemImage: "books.vertical.circle.fill")
                                }
                                .id(SearchSelection.library)
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
                .onChange(of: router.dismiss) {
                    dismiss()
                }
            case .notDetermined:
                AppleMusicPermissionsView()
                    .environment(musicSearchService)
                    .addDismiss(action: dismiss.callAsFunction)
            case .denied:
                ImprovedSearch(adding: .constant(nil), group: group)
            }
        }
        .onAppear {
            musicSearchService.query = ""
            searchFieldIsPresented = true
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
    }

    @MainActor
    private func showKeyboard() {
        UIView.setAnimationsEnabled(false)
        Task {
            try await Task.sleep(for: .milliseconds(400))
            UIView.setAnimationsEnabled(true)
        }
    }

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
            Image(systemName: "books.vertical.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        }
    }
}

#Preview {
    NewSearchScreen(group: nil)
        .environment(SonosService.shared)
}

