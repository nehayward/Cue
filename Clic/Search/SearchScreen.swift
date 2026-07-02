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
    @Environment(MiniPlayerManger.self) private var miniPlayerManager

    @AppStorage(AppStorageKeys.mediaService) private var musicSearchSelection: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.searchAlsoServices) private var searchAlsoServicesRaw: String = ""
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined
    @AppStorage(AppStorageKeys.defaultPlayAction) private var replaceQueueByDefault: Bool = false
    var favorites: Bool = false
    var closeInspector: (() -> Void)? = nil

    var isAlarmSearch: Bool = false
    @State private var coreFeatures = CoreFeatures.shared
    @State private var alertService = AlertService.shared
    @State private var searchCompletionTapped: Bool = false
    @State private var suggestion: String? = nil
    @State private var searchFieldIsPresented: Bool = true
    @State private var filters: [FilterSelection] = FilterSelection.defaultFilters
    @State private var plexLibrariesFilters: [GenericFilter<PlexLibrarySection>] = []

    @FocusState private var focusedField: SearchFocusFields?
    #if targetEnvironment(macCatalyst)
    @State private var searchBarFocused: Bool = false
    #endif

    @State private var recentQueries = RecentQueriesStorage.shared
    @State private var lastNonEmptyQuery: String = ""
    @State private var isLoading: Bool = false
    @State private var keyboardSelectedIndex: Int?

    private var showAlert: Bool {
#if targetEnvironment(macCatalyst)
        return false
#else
        return UIDevice.current.userInterfaceIdiom == .phone
#endif
    }

    private var suggestionCountForNav: Int {
#if targetEnvironment(macCatalyst)
        !searchCompletionTapped ? musicSearchService.suggestions.count : 0
#else
        0
#endif
    }

    /// The primary service plus any "Also Search" services from the menu.
    /// Extras only count while their service is enabled in Settings.
    private var selectedSearchServices: Set<MediaSearchService> {
        MediaSearchService.set(fromRawList: searchAlsoServicesRaw)
            .filter { coreFeatures.enabledServices($0).wrappedValue }
            .union([musicSearchSelection])
    }

    private var currentFilteredResults: [PlayableContent] {
        guard !musicSearchService.query.isEmpty else { return [] }
        return musicSearchService.results.filtered(by: filters)
    }

    private var navigableCount: Int {
        suggestionCountForNav + currentFilteredResults.count
    }

    private var selectedItemID: String? {
        guard let idx = keyboardSelectedIndex else { return nil }
        let suggCount = suggestionCountForNav
        guard idx >= suggCount else { return nil }
        let resultIdx = idx - suggCount
        guard resultIdx < currentFilteredResults.count else { return nil }
        return currentFilteredResults[resultIdx].id
    }

    var body: some View {
        @Bindable var router = router
        @Bindable var musicSearchService = musicSearchService
        @Bindable var sonosService = sonosService

        NavigationStack(path: $router.path) {
            ScrollViewReader { proxy in
                List(selection: .constant(selectedItemID)) {
                    SearchFilterRow(
                        musicSearchSelection: $musicSearchSelection,
                        filters: $filters,
                        plexLibrariesFilters: $plexLibrariesFilters
                    )

#if targetEnvironment(macCatalyst)
                    if !searchCompletionTapped {
                        MacCatalystSuggestionsList(
                            searchCompletionTapped: $searchCompletionTapped,
                            suggestion: $suggestion,
                            keyboardSelectedIndex: $keyboardSelectedIndex
                        )
                    }
#endif

                    if musicSearchService.query.isEmpty {
                        SearchEmptyStateView(
                            isAlarmSearch: isAlarmSearch,
                            service: musicSearchSelection,
                            filters: $filters
                        )
                    } else {
                        SearchResultsView(
                            service: musicSearchSelection,
                            isMultiService: selectedSearchServices.count > 1,
                            query: $musicSearchService.query,
                            filters: $filters,
                            plexLibrariesFilters: $plexLibrariesFilters
                        )
                    }

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .listRowSeparator(.hidden)
                    }
                }
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
                .onChange(of: keyboardSelectedIndex) {
                    if let id = selectedItemID {
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .principal) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search", text: $musicSearchService.query)
                                .focused($focusedField, equals: .search)
                                .onSubmit {
                                    guard let idx = keyboardSelectedIndex else { return }
                                    activateSelectedItem(at: idx)
                                }
                        }
                        .frame(idealWidth: 800)
                        .toolbarBackground(with: true, in: .capsule)
                        #if targetEnvironment(macCatalyst)
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                .opacity(searchBarFocused ? 1 : 0)
                        }
                        #endif
                    }
                    #if !os(visionOS)
                    if #available(iOS 26.0, *) {
                        ToolbarItemGroup(placement: .keyboard) {
                            SearchSuggestionsBar(
                                searchCompletionTapped: $searchCompletionTapped,
                                suggestion: $suggestion,
                                hideKeyboard: hideKeyboard
                            )
                        }
                        .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItemGroup(placement: .keyboard) {
                            SearchSuggestionsBar(
                                searchCompletionTapped: $searchCompletionTapped,
                                suggestion: $suggestion,
                                hideKeyboard: hideKeyboard
                            )
                        }
                    }
                    #endif

                    ToolbarItem(placement: .topBarTrailing) {
                        MediaServiceMenu(
                            musicSearchSelection: $musicSearchSelection,
                            filters: $filters,
                            searchAlsoServicesRaw: $searchAlsoServicesRaw
                        )
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task(id: musicSearchService.query + musicSearchSelection.rawValue + searchAlsoServicesRaw) {
                isLoading = true
                if suggestion == nil {
                    searchCompletionTapped = false
                }
                // Ranking boosts items the user has played; injected here so
                // SonosKit stays free of app-side play-history state.
                musicSearchService.recentlyPlayedIDs = Set(playHistoryService.history.prefix(50).map(\.id))
                await musicSearchService.search(for: selectedSearchServices)
                suggestion = nil
                isLoading = false
                playlistsContainer.playlists = await sonosService.sonosPlaylists()
            }
            .animation(.snappy, value: playHistoryService.history)
            .animation(.snappy, value: musicSearchService.results)
            .animation(.snappy, value: filters)
            .animation(.snappy, value: searchCompletionTapped)
            .addDismiss(override: contentToAdd != nil) {
                dismiss()
            }
            .withAppRouter()
        }
        .withAlert(enabled: showAlert)
        .keyboardType(.asciiCapable)
        .autocorrectionDisabled()
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in
            let count = navigableCount
            guard count > 0 else { return .ignored }
            if let idx = keyboardSelectedIndex {
                keyboardSelectedIndex = min(idx + 1, count - 1)
            } else {
                keyboardSelectedIndex = 0
            }
            return .handled
        }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in
            guard keyboardSelectedIndex != nil else { return .ignored }
            if let idx = keyboardSelectedIndex, idx > 0 {
                keyboardSelectedIndex = idx - 1
            } else {
                keyboardSelectedIndex = nil
            }
            return .handled
        }
        .onKeyPress(.return) {
            guard let idx = keyboardSelectedIndex else { return .ignored }
            activateSelectedItem(at: idx)
            return .handled
        }
        .onKeyPress(.escape) {
            guard keyboardSelectedIndex != nil else { return .ignored }
            keyboardSelectedIndex = nil
            return .handled
        }
        .background {
            TextField("Search", text: $musicSearchService.query)
                .focusOnAppear($focusedField, equals: .search)
                .onSubmit {
                    guard let idx = keyboardSelectedIndex else { return }
                    activateSelectedItem(at: idx)
                }
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
        .onChange(of: musicSearchService.query) {
            keyboardSelectedIndex = nil
            if !musicSearchService.query.isEmpty {
                lastNonEmptyQuery = musicSearchService.query
            }
        }
        .onChange(of: musicSearchSelection) {
            keyboardSelectedIndex = nil
            musicSearchService.results = []
        }
        .onChange(of: searchAlsoServicesRaw) {
            keyboardSelectedIndex = nil
            musicSearchService.results = []
        }
        .onChange(of: filters) {
            keyboardSelectedIndex = nil
        }
#if !targetEnvironment(macCatalyst)
        .safeArea(edge: .bottom) {
            if contentToAdd == nil, !miniPlayerManager.hidden {
                MiniPlayerView()
                    .geometryGroup()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
#endif
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            if favorites { return }
            searchFieldIsPresented = true
            lastNonEmptyQuery = ""
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
        .onDisappear {
            if !lastNonEmptyQuery.isEmpty {
                recentQueries.addOrMoveToFront(lastNonEmptyQuery)
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
        #if targetEnvironment(macCatalyst)
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { _ in
            searchBarFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { _ in
            searchBarFocused = false
        }
        #endif
    }

    @MainActor
    private func showKeyboard() {
        UIView.setAnimationsEnabled(false)
        Task {
            try await Task.sleep(for: .milliseconds(300))
            UIView.setAnimationsEnabled(true)
        }
    }

    private func activateSelectedItem(at index: Int) {
        let suggCount = suggestionCountForNav
        if index < suggCount {
            let suggestion = musicSearchService.suggestions[index]
            musicSearchService.query = suggestion.searchTerm
            self.suggestion = suggestion.searchTerm
            searchCompletionTapped = true
            keyboardSelectedIndex = nil
            return
        }
        let resultIndex = index - suggCount
        guard resultIndex < currentFilteredResults.count else { return }
        activateItem(currentFilteredResults[resultIndex])
    }

    private func activateItem(_ item: PlayableContent) {
        keyboardSelectedIndex = nil
        hideKeyboard()
        switch item.content.type {
        case .playlist, .album, .libraryPlaylist, .libraryAlbum, .libraryImportedPlaylists:
            router.path.append(RouterDestination.mediaDetail(content: item, group: selectedGroupService.group))
        case .artist, .libraryArtist:
            router.path.append(RouterDestination.artistDetail(content: item, group: selectedGroupService.group))
        case .folder:
            router.path.append(RouterDestination.folderBrowse(item: item, title: item.title))
        default:
            playItem(item)
        }
    }

    private func playItem(_ item: PlayableContent) {
        if contentToAdd?.add == true {
            contentToAdd?.content = item
            return
        }
        Task { @MainActor in
            let position = QueuePosition.defaultPosition(for: item.content.type, replaceQueueByDefault: replaceQueueByDefault)
            guard let group = selectedGroupService.group else {
                router.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onQueueSelection: { group, selectedPosition in
                    QueueManager.shared.addToQueue(item: QueueItem(playableContent: item, group: group, position: selectedPosition, title: selectedPosition.title))
                    Router.main.show(destination: .player(groupID: group.coordinatorID))
                }, defaultPosition: position, content: item))
                return
            }
            QueueManager.shared.addToQueue(item: QueueItem(playableContent: item, group: group, position: position, title: position.title))
            Router.main.show(destination: .player(groupID: group.coordinatorID))
        }
    }
}

// MARK: - Subviews

private struct SearchFilterRow: View {
    @Binding var musicSearchSelection: MediaSearchService
    @Binding var filters: [FilterSelection]
    @Binding var plexLibrariesFilters: [GenericFilter<PlexLibrarySection>]

    @Environment(MusicSearchService.self) private var musicSearchService

    var body: some View {
        Group {
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
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
        .overlay(alignment: .trailing) {
            if musicSearchSelection == .plex {
                ZStack(alignment: .trailing) {
                    // Transparent hit area to block taps below
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .allowsHitTesting(true)
                    PlexLibraryFilterView(plexLibrariesFilters: $plexLibrariesFilters)
                }
                .frame(width: 24, height: 24)
                .task {
                    let libraries = await musicSearchService.getPlexLibraries()
                    plexLibrariesFilters = libraries.map { GenericFilter(filter: $0) }
                }
            }
        }
    }
}

private struct SearchEmptyStateView: View {
    let isAlarmSearch: Bool
    let service: MediaSearchService
    @Binding var filters: [FilterSelection]

    @Environment(PlayHistoryService.self) private var playHistoryService

    var body: some View {
        if !isAlarmSearch {
            RecentSearchesView()
        }

        if !playHistoryService.history.isEmpty {
            PlayHistoryView(filters: $filters)
        }

        if !isAlarmSearch, service == .spotify {
            SpotifySearchScreen()
        }

        if !isAlarmSearch, service == .apple {
            ApplePlaylistsView()
        }

        if !isAlarmSearch {
            FavoritesView()
                .id("favorites")
        }
    }
}

private struct SearchResultsView: View {
    let service: MediaSearchService
    let isMultiService: Bool
    @Binding var query: String
    @Binding var filters: [FilterSelection]
    @Binding var plexLibrariesFilters: [GenericFilter<PlexLibrarySection>]

    @Environment(MusicSearchService.self) private var musicSearchService

    var body: some View {
        if isMultiService {
            // Merged multiservice results are one ranked list; the generic
            // view renders rows for any service.
            ServiceSearchView(results: musicSearchService.results, filters: $filters)
        } else {
            switch service {
            case .spotify:
                SpotifySearchView(results: musicSearchService.results, filters: $filters)
            case .apple:
                AppleMusicSearchScreen(results: musicSearchService.results, filters: $filters)
            case .library:
                LibrarySearchView(results: musicSearchService.results, filters: $filters)
            case .plex:
                PlexSearchView(
                    query: $query,
                    results: musicSearchService.results,
                    filters: $filters,
                    plexLibrariesFilters: $plexLibrariesFilters
                )
            case .tidal:
                TidalSearchView(results: musicSearchService.results, filters: $filters)
            case .tuneIn:
                TuneInSearchView(results: musicSearchService.results, filters: $filters)
            default:
                // ServiceSearchView handles all remaining services (SoundCloud, Deezer, etc.)
                // New services get a working generic search view without touching this switch.
                ServiceSearchView(results: musicSearchService.results, filters: $filters)
            }
        }
    }
}

#if targetEnvironment(macCatalyst)
private struct MacCatalystSuggestionsList: View {
    @Binding var searchCompletionTapped: Bool
    @Binding var suggestion: String?
    @Binding var keyboardSelectedIndex: Int?

    @Environment(MusicSearchService.self) private var musicSearchService

    var body: some View {
        ForEach(Array(musicSearchService.suggestions.enumerated()), id: \.element.id) { index, suggestion in
            Button {
                musicSearchService.query = suggestion.searchTerm
                self.suggestion = suggestion.searchTerm
                searchCompletionTapped = true
                keyboardSelectedIndex = nil
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text(suggestion.displayTerm)
                    Spacer()
                }
                .foregroundStyle(.accent)
            }
            .listRowBackground(
                keyboardSelectedIndex == index ?
                    RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)) : nil
            )
        }
    }
}
#endif

private struct MediaServiceMenu: View {
    @Binding var musicSearchSelection: MediaSearchService
    @Binding var filters: [FilterSelection]
    @Binding var searchAlsoServicesRaw: String

    @Environment(Router.self) private var router
    @State private var coreFeatures = CoreFeatures.shared

    private var alsoSearchServices: Set<MediaSearchService> {
        MediaSearchService.set(fromRawList: searchAlsoServicesRaw)
            .subtracting([musicSearchSelection])
    }

    var body: some View {
        Menu {
            ForEach(MediaSearchService.allCases, id: \.self) { service in
                if coreFeatures.enabledServices(service).wrappedValue {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        musicSearchSelection = service
                        // The new primary can't also be an extra.
                        searchAlsoServicesRaw = alsoSearchServices.subtracting([service]).rawList
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
            alsoSearchSection
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                router.presentedSheet = .settings(destination: .servicePreferenceScreen)
            } label: {
                Label("Settings…", systemImage: "gear")
            }
        } label: {
            musicSearchSelection
                .iconForMusicService
                .frame(width: 24, height: 24)
                .contentShape(.circle)
                .toolbarBackground(in: .circle)
                .overlay(alignment: .topTrailing) {
                    if !alsoSearchServices.isEmpty {
                        Text("+\(alsoSearchServices.count)")
                            .font(.system(size: 9, weight: .bold))
                            .padding(3)
                            .background(.thinMaterial, in: .circle)
                            .offset(x: 8, y: -8)
                    }
                }
        }
        .popoverTip(AppTip.mediaService)
        .foregroundStyle(musicSearchSelection.brandColor.gradient)
    }

    /// Extra services searched together with the primary one, merged into a
    /// single ranked result list. TuneIn stays single-service — a radio
    /// directory doesn't mix into a catalog search.
    private var alsoSearchSection: some View {
        Section("Also Search") {
            ForEach(MediaSearchService.allCases, id: \.self) { service in
                if service != musicSearchSelection,
                   service != .tuneIn,
                   coreFeatures.enabledServices(service).wrappedValue {
                    Toggle(isOn: alsoSearchBinding(for: service)) {
                        HStack {
                            Text(service.title)
                            service.iconForMusicService
                        }
                    }
                }
            }
        }
    }

    private func alsoSearchBinding(for service: MediaSearchService) -> Binding<Bool> {
        Binding(
            get: { alsoSearchServices.contains(service) },
            set: { include in
                HapticManager.shared.fireHaptic(.buttonPress)
                var services = alsoSearchServices
                if include {
                    services.insert(service)
                } else {
                    services.remove(service)
                }
                searchAlsoServicesRaw = services.rawList
            }
        )
    }
}

extension MediaSearchService {
    static func set(fromRawList raw: String) -> Set<MediaSearchService> {
        Set(raw.split(separator: ",").compactMap { MediaSearchService(rawValue: String($0)) })
    }
}

extension Collection where Element == MediaSearchService {
    /// Stable comma-separated form for AppStorage (sorted so the search
    /// `.task(id:)` string doesn't churn on set-order changes).
    var rawList: String {
        map(\.rawValue).sorted().joined(separator: ",")
    }
}

private struct SearchSuggestionsBar: View {
    @Binding var searchCompletionTapped: Bool
    @Binding var suggestion: String?
    let hideKeyboard: () -> Void

    @Environment(MusicSearchService.self) private var musicSearchService
    @State private var recentQueries = RecentQueriesStorage.shared

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                if !recentQueries.object.isEmpty, musicSearchService.query.isEmpty {
                    ForEach(recentQueries.object.reversed(), id: \.self) { query in
                        recentQueryButton(query)
                    }
                } else {
                    ForEach(musicSearchService.suggestions) { suggestion in
                        suggestionButton(suggestion)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .mask(
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1)
            ], startPoint: .leading, endPoint: .trailing)
        )
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func recentQueryButton(_ query: String) -> some View {
        if #available(iOS 26.0, *) {
            Button {
                musicSearchService.query = query
                suggestion = query
                searchCompletionTapped = true
                hideKeyboard()
            } label: {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                    Text(query)
                    Spacer()
                }
            }
#if !os(visionOS)
            .buttonStyle(.glass)
#endif
        } else {
            Button {
                musicSearchService.query = query
                suggestion = query
                searchCompletionTapped = true
            } label: {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                    Text(query)
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

    @ViewBuilder
    private func suggestionButton(_ suggestionItem: MusicCatalogSearchSuggestionsResponse.Suggestion) -> some View {
        if #available(iOS 26.0, *) {
            Button {
                musicSearchService.query = suggestionItem.searchTerm
                suggestion = suggestionItem.searchTerm
                searchCompletionTapped = true
                hideKeyboard()
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text(suggestionItem.displayTerm)
                    Spacer()
                }
            }
#if !os(visionOS)
            .buttonStyle(.glass)
#endif
        } else {
            Button {
                musicSearchService.query = suggestionItem.searchTerm
                suggestion = suggestionItem.searchTerm
                searchCompletionTapped = true
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text(suggestionItem.displayTerm)
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

#Preview("Empty") {
    SearchScreen()
        .environment(Router.search)
        .forPreview()
}
