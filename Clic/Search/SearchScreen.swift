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
import FocusOnAppear

struct SearchScreen: View {
    enum SearchFocusFields: Hashable {
        case search
    }
    
    @Environment(\.dismiss) private var dismiss

    @Environment(SonosService.self) private var sonosService: SonosService
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(Router.self) private var router: Router
    @Environment(PlaylistContainer.self) private var playlistsContainer
    @Environment(PlayHistoryService.self) private var playHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService
    @Environment(ContentToAdd.self) private var contentToAdd: ContentToAdd?
    @Environment(AppleMusicBrowseService.self) private var appleMusicBrowseService

    @AppStorage(AppStorageKeys.mediaService) private var musicSearchSelection: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    var favorites: Bool = false
    var closeInspector: (() -> Void)? = nil

    var isAlarmSearch: Bool = false
    @State private var coreFeatures = CoreFeatures.shared
    @State private var alertService = AlertService.shared
    @State private var searchCompletionTapped: Bool = false
    @State private var suggestion: String? = nil
    @State private var searchFieldIsPresented: Bool = true
    @State private var filters: [FilterSelection] = FilterSelection.defaultFilters
    
    @FocusState private var focusedField: SearchFocusFields?

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
            ScrollViewReader { proxy in
                List {
                    filterView
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
//                    if UIApplication.shared.isRunningInTestFlightEnvironment(), musicSearchSelection == .plex {
//                        LoggerView()
//                    }
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
                        SpotifySearchScreen()
                    }
                    
                    if musicSearchService.query.isEmpty, !isAlarmSearch,  musicSearchSelection == .apple {
                        ApplePlaylistsView()
                    }
                    
                    if musicSearchService.query.isEmpty, !isAlarmSearch {
                        FavoritesView()
                            .id("favorites")
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
                .listSectionSpacing(12)
                .onAppear {
                    if favorites {
                        searchFieldIsPresented = false
                        Task {
                            await sonosService.getFavoriteList()
                            try? await Task.sleep(for: .milliseconds(300))
                            withAnimation {
                                proxy.scrollTo("favorites", anchor: .top)
                            }
                        }
                        return
                    }
                }
                .ignoresSafeArea(.keyboard)
                .contentMargins(.bottom, 120, for: .scrollContent)
#if !os(visionOS)
                .scrollDismissesKeyboard(.immediately)
#endif
                .toolbar {
                    ToolbarItemGroup(placement: .principal) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search", text: $musicSearchService.query)
                                .focused($focusedField, equals: .search)
                        }
                        .frame(idealWidth: 800)
                        .toolbarBackground(with: true, in: .capsule)
                    }
                    
                    ToolbarItemGroup(placement: .keyboard) {
                        searchSuggestions
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
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
                                            service.iconForMusicService
                                        }
                                        .tag(service)
                                    }
                                    .tint(service.brandColor.gradient)
                                    .id(service)
                                }
                            }
                            Button {
                                HapticManager.shared.fireHaptic(.buttonPress)
                                router.presentedSheet = .settings(destination: .servicePreferenceScreen)
                            } label: {
                                Label("Setting…", systemImage: "gear")
                            }
                        } label: {
                            musicSearchSelection
                                .iconForMusicService
                                .frame(width: 24, height: 24)
                                .toolbarBackground(in: .circle)
                        }
                        .popoverTip(AppTip.mediaService)
                        .foregroundStyle(musicSearchSelection.brandColor.gradient)
                    }
                }
            }
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
            #if !targetEnvironment(macCatalyst)
            .addDismiss(override: contentToAdd != nil) {
                dismiss()
                closeInspector?()
            }
            #endif
            .withAppRouter()
        }
        .withAlert(enabled: showAlert)
        .animation(.spring, value: alertService.alert.isShowing)
        .keyboardType(.asciiCapable)
        .autocorrectionDisabled()
        .background {
            TextField("Search", text: $musicSearchService.query)
                .focusOnAppear($focusedField, equals: .search)
                .task {
                    try? await Task.sleep(for: .seconds(0.6))
                    focusedField = .search
                }
                .opacity(0.01)
        }
        .presentationDragIndicator(.hidden)
        .listStyle(.plain)
        .foregroundStyle(.primary)
        .environment(router)
        .environment(musicSearchService)
        .environment(alertService)
        .onChange(of: contentToAdd?.content) {
            dismiss()
        }
#if !targetEnvironment(macCatalyst)
        .safeArea(edge: .bottom) {
            if contentToAdd == nil{
                MiniPlayerView()
            }
        }
#endif
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            if favorites { return }
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
        .animation(.interactiveSpring, value: focusedField)
        .animation(.interactiveSpring, value: musicSearchService.suggestions)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .overlay(
            Button {
                closeInspector?()
            } label: {
                EmptyView()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .frame(width: 0, height: 0)
            .hidden()
        )
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
    @ViewBuilder
    private var filterView: some View {
        if musicSearchSelection != .tuneIn {
            VStack(spacing: 0) {
                HStack {
                    FilterView(selectedService: $musicSearchSelection, filters: $filters)
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }
    
    private var searchSuggestions: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(musicSearchService.suggestions) { suggestion in
                    if #available(iOS 26.0, *) {
                        Button {
                            musicSearchService.query = suggestion.searchTerm
                            self.suggestion = suggestion.searchTerm
                            searchCompletionTapped = true
                            hideKeyboard()
                        } label: {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                Text(suggestion.displayTerm)
                                Spacer()
                            }
                        }
                        .buttonStyle(.glass)
                    } else {
                        Button {
                            musicSearchService.query = suggestion.searchTerm
                            self.suggestion = suggestion.searchTerm
                            searchCompletionTapped = true
//                            hideKeyboard()
                        } label: {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                Text(suggestion.displayTerm)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                        .background(.thinMaterial, in: .capsule)
                    }
                }
            }
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
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
