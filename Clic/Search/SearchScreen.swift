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
    @AppStorage(AppStorageKeys.searchAlsoServices) private var searchAlsoServices: AlsoSearchServices = []
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
    /// Query+services of the last search that ran to completion; lets the
    /// `.task` below skip an identical re-search when it re-fires on
    /// navigation back from a detail.
    @State private var lastCompletedSearchKey: String?
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
    /// TuneIn is a radio directory and always searches alone — leftover
    /// extras from a previous primary must not merge radio with catalogs.
    private var selectedSearchServices: Set<MediaSearchService> {
        guard musicSearchSelection != .tuneIn else { return [.tuneIn] }
        return searchAlsoServices.services
            .filter { coreFeatures.enabledServices($0).wrappedValue }
            .union([musicSearchSelection])
    }

    /// Mirrors AppleMusicSearchScreen: a single-service Apple search without
    /// authorization renders the permissions prompt instead of results.
    private var showsApplePermissionsPrompt: Bool {
        musicSearchSelection == .apple
            && selectedSearchServices.count == 1
            && appleMusicAuthorized != .authorized
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
                        isMultiService: selectedSearchServices.count > 1,
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

                        if !isLoading, currentFilteredResults.isEmpty, !showsApplePermissionsPrompt {
                            ContentUnavailableView.search(text: musicSearchService.query)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
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

                    if #available(iOS 26.0, *) {
                        ToolbarItem(placement: .topBarTrailing) {
                            MediaServiceMenu(
                                musicSearchSelection: $musicSearchSelection,
                                filters: $filters,
                                searchAlsoServices: $searchAlsoServices
                            )
                        }
                    } else {
                        ToolbarItem(placement: .topBarTrailing) {
                            MediaServiceMenu(
                                musicSearchSelection: $musicSearchSelection,
                                filters: $filters,
                                searchAlsoServices: $searchAlsoServices
                            )
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task(id: musicSearchService.query + musicSearchSelection.rawValue + searchAlsoServices.rawValue) {
                // Pushing a detail cancels this task and popping back restarts
                // it — same id, but `.task` re-fires on reappear. Re-running
                // the identical search re-streams providers into the list and
                // re-sorts it, visibly reshuffling results on every return.
                // If nothing changed since the last completed search, keep
                // what's on screen.
                let searchKey = musicSearchService.query + musicSearchSelection.rawValue + searchAlsoServices.rawValue
                if searchKey == lastCompletedSearchKey, !musicSearchService.results.isEmpty {
                    isLoading = false
                    return
                }
                isLoading = true
                if suggestion == nil {
                    searchCompletionTapped = false
                }
                // Ranking boosts items the user has played; injected here so
                // SonosKit stays free of app-side play-history state.
                musicSearchService.recentlyPlayedIDs = Set(playHistoryService.history.prefix(50).map(\.id))
                await musicSearchService.search(for: selectedSearchServices)
                // A cancelled task (query/service changed) must not clear
                // isLoading under the replacement search — that briefly
                // showed "No Results" while the real search was in flight.
                if Task.isCancelled { return }
                lastCompletedSearchKey = searchKey
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
        // A new primary service is a different result set — drop stale results
        // immediately (a query edit deliberately keeps old results to avoid
        // flicker while typing).
        .onChange(of: musicSearchSelection) {
            keyboardSelectedIndex = nil
            musicSearchService.results = []
        }
        // Toggling an extra does NOT clear results: the merged search updates
        // them in place, so the list doesn't flash empty behind the still-open
        // menu (which read as flicker / the menu "closing").
        .onChange(of: searchAlsoServices) {
            keyboardSelectedIndex = nil
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
    let isMultiService: Bool
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
            // The per-library filter only applies in the Plex-only view;
            // merged multiservice results would silently ignore it.
            if musicSearchSelection == .plex, !isMultiService {
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
    @Binding var searchAlsoServices: AlsoSearchServices

    @State private var coreFeatures = CoreFeatures.shared

    /// The extras actually in effect: matches SearchScreen.selectedSearchServices
    /// — disabled services don't count (no phantom badge for a service the
    /// search skips), and a TuneIn primary always searches alone.
    private var activeExtras: Set<MediaSearchService> {
        guard musicSearchSelection != .tuneIn else { return [] }
        return searchAlsoServices.services
            .filter { coreFeatures.enabledServices($0).wrappedValue }
            .subtracting([musicSearchSelection])
    }

    /// Active extras in a stable display order (the enum's case order), for the
    /// overlapping-icon badge.
    private var activeExtrasOrdered: [MediaSearchService] {
        MediaSearchService.allCases.filter { activeExtras.contains($0) }
    }

    /// Every service being searched — primary first, then active extras in
    /// stable order — for the overlapping toolbar icon.
    private var selectedServicesOrdered: [MediaSearchService] {
        [musicSearchSelection] + activeExtrasOrdered
    }

    private let maxSelectable = 3

    private var enabledServices: [MediaSearchService] {
        MediaSearchService.allCases.filter { coreFeatures.enabledServices($0).wrappedValue }
    }

    /// A service is included in the search when it's the primary or an extra.
    private func isSelected(_ service: MediaSearchService) -> Bool {
        service == musicSearchSelection || activeExtras.contains(service)
    }

    private var selectedCount: Int { 1 + activeExtras.count }
    private var isAtLimit: Bool { selectedCount >= maxSelectable }

    var body: some View {
        // The icon stack is plain SwiftUI; the menu is presented by a
        // transparent UIKit button overlaid on it. A SwiftUI Menu in a
        // toolbar tears down whenever its label changes — every toggle
        // rebuilt the bar item and dismissed the menu. A UIButton's presented
        // menu survives label updates underneath it, `.keepsMenuPresented`
        // keeps it open across toggles, and `updateVisibleMenu` refreshes the
        // checkmarks and disabled states in place. (Not a popover either:
        // those crash on Mac Catalyst; on Mac the menu natively closes per
        // click, which is expected there.)
        OverlappingServiceIcons(services: selectedServicesOrdered)
            .overlay {
                ServiceMenuPresenter(items: menuItems)
                    // Grow the tap target past the small icon stack.
                    .padding(-10)
            }
            .popoverTip(AppTip.mediaService)
    }

    private func menuItems() -> [ServiceMenuPresenter.Item] {
        enabledServices.map { service in
            ServiceMenuPresenter.Item(
                title: service.title,
                image: service.menuImage,
                isOn: isSelected(service),
                isDisabled: isAtLimit && !isSelected(service),
                handler: { toggleService(service) }
            )
        }
    }

    /// Toggle a service in/out of the search set (max 3). Primary + extras are
    /// kept internally; the primary is just the first selected. TuneIn is
    /// exclusive — a radio directory doesn't mix into a catalog search.
    private func toggleService(_ service: MediaSearchService) {
        HapticManager.shared.fireHaptic(.buttonPress)

        if service == .tuneIn {
            setPrimary(.tuneIn, clearingExtras: true)
            for filter in filters { filter.isFiltered = false }
            return
        }
        if musicSearchSelection == .tuneIn {
            // Leaving TuneIn: the tapped service becomes the sole primary.
            setPrimary(service, clearingExtras: true)
            return
        }

        if service == musicSearchSelection {
            // Uncheck the primary by promoting an extra; no-op if it's the last.
            guard let next = activeExtrasOrdered.first else { return }
            searchAlsoServices.services.remove(next)
            setPrimary(next, clearingExtras: false)
        } else if activeExtras.contains(service) {
            searchAlsoServices.services.remove(service)
        } else if selectedCount < maxSelectable {
            searchAlsoServices.services.insert(service)
        }
    }

    private func setPrimary(_ service: MediaSearchService, clearingExtras: Bool) {
        musicSearchSelection = service
        if clearingExtras {
            searchAlsoServices.services.removeAll()
        } else {
            searchAlsoServices.services.remove(service)
        }
        Analytics.shared.track(.selectedMusicService, with: ["MusicService": service.rawValue])
        Analytics.shared.setSelection(metadata: ["MusicService": service.rawValue])
    }
}

/// Up to three overlapping, brand-colored service icons — the search menu's
/// toolbar button. With a single service it's just that icon; with extras
/// they stack "avatar pile" style, the trailing (primary-most-recent) chip on
/// top. Deliberately plain: an earlier version cut a masked seam between the
/// chips, but the mask's compositing layer glitched and clipped while the
/// stack animated between selection sizes, so the chips simply overlap.
private struct OverlappingServiceIcons: View {
    let services: [MediaSearchService]
    var diameter: CGFloat = 26

    private var shown: [MediaSearchService] { Array(services.prefix(3)) }
    private var overlap: CGFloat { diameter * 0.45 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(shown, id: \.self) { service in
                service.iconForMusicService
                    .foregroundStyle(service.brandColor.gradient)
                    .frame(width: diameter, height: diameter)
            }
        }
    }
}

/// A transparent `UIButton` that presents the service menu natively. UIKit is
/// the point: SwiftUI's `Menu` dismisses when its toolbar label changes (each
/// toggle rebuilt the bar item), while a UIButton's presented menu survives
/// label updates, `.keepsMenuPresented` keeps it open across toggles, and
/// `updateVisibleMenu` refreshes checkmarks/disabled states in place. The
/// deferred uncached element re-reads `items` on every presentation, so the
/// menu always reflects current state without the button itself changing.
private struct ServiceMenuPresenter: UIViewRepresentable {
    struct Item {
        let title: String
        let image: UIImage?
        let isOn: Bool
        let isDisabled: Bool
        let handler: () -> Void
    }

    /// Re-invoked at every menu (re)display — must read live state.
    var items: () -> [Item]

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        button.backgroundColor = .clear
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = String(localized: "Search Services")
        context.coordinator.items = items
        context.coordinator.button = button
        button.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak coordinator = context.coordinator] completion in
                completion(coordinator?.menuElements() ?? [])
            }
        ])
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        context.coordinator.items = items
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var items: () -> [Item] = { [] }
        weak var button: UIButton?

        func menuElements() -> [UIMenuElement] {
            items().map { item in
                var attributes: UIMenuElement.Attributes = [.keepsMenuPresented]
                if item.isDisabled { attributes.insert(.disabled) }
                return UIAction(
                    title: item.title,
                    image: item.image,
                    attributes: attributes,
                    state: item.isOn ? .on : .off
                ) { [weak self] _ in
                    item.handler()
                    self?.refreshVisibleMenu()
                }
            }
        }

        /// Re-resolves the still-presented menu after a toggle so checkmarks
        /// and at-limit disabled states update in place; async so the
        /// SwiftUI state write lands first.
        private func refreshVisibleMenu() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let button = self.button else { return }
                let refreshed = UIMenu(children: self.menuElements())
                button.contextMenuInteraction?.updateVisibleMenu { _ in refreshed }
            }
        }
    }
}

/// The "Also Search" extras, stored in `@AppStorage` as a typed set instead
/// of a bare `String`. `RawRepresentable` lets `@AppStorage` persist it as the
/// same sorted comma-separated raw-value string (so existing stored values
/// keep working with no migration), while call sites work with a real `Set`
/// and never re-parse the string themselves. Sorting keeps the search
/// `.task(id:)` stable across set-order changes.
struct AlsoSearchServices: RawRepresentable, Equatable, ExpressibleByArrayLiteral {
    var services: Set<MediaSearchService>

    init(_ services: Set<MediaSearchService> = []) { self.services = services }
    init(arrayLiteral elements: MediaSearchService...) { self.services = Set(elements) }

    init(rawValue: String) {
        services = Set(rawValue.split(separator: ",").compactMap { MediaSearchService(rawValue: String($0)) })
    }

    var rawValue: String {
        services.map(\.rawValue).sorted().joined(separator: ",")
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
