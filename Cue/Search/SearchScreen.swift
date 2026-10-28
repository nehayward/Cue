import CloudStorage
import MusicSearchKit
import Defaults
import NukeUI
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit

struct SearchScreen: View {
    enum SearchFocusFields: Hashable {
        case search
    }

    @Environment(\.usesPadLayout) private var usesPadLayout

    @Environment(SonosService.self) private var sonosService: SonosService
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(Router.self) private var router: Router
    @Environment(PlayHistoryService.self) private var playHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService
    @Environment(ContentToAdd.self) private var contentToAdd: ContentToAdd?
    @Environment(AppleMusicBrowseService.self) private var appleMusicBrowseService
    @Environment(MiniPlayerManger.self) private var miniPlayerManager

    // No `@AppStorage` and no `dismiss` held here: either made the whole
    // screen rebuild, hidden or not, on every UserDefaults write, every tab
    // switch and return to Cue (`CueApp` re-running), and every frame of
    // the keyboard coming back. Settings are observed (`SearchSelectionStore`)
    // or read when used, and `dismiss` only in `DismissesSearch`.
    @State private var selectionStore = SearchSelectionStore.shared

    private var searchSelection: SelectedSearchServices {
        get { selectionStore.selection }
        nonmutating set { selectionStore.selection = newValue }
    }

    /// Asked of MusicKit, which answers at once; the search service's
    /// status is read too, so a grant made here shows at once.
    private var isAppleMusicAuthorized: Bool {
        musicSearchService.appleMusicAuthorizationStatus == .authorized
            || MusicAuthorization.currentStatus == .authorized
    }
    var favorites: Bool = false
    var closeInspector: (() -> Void)? = nil

    var isAlarmSearch: Bool = false
    /// The Search tab's own screen, which alone answers the tab bar's
    /// requests for the field (`SearchActivator`); the same screen in a
    /// sheet (Sonos Favorites, an alarm's) opens without the keyboard.
    var isTab: Bool = false
    @State private var coreFeatures = CoreFeatures.shared
    @State private var alertService = AlertService.shared
    /// Offline, the field searches what's on this device instead of the
    /// services (`OfflineSearchView`); the services menu and filters go.
    @State private var offline = OfflineMode.shared
    @State private var offlineSearch = OfflineSearch()
    @State private var searchCompletionTapped: Bool = false
    @State private var suggestion: String? = nil
    @State private var searchFieldIsPresented: Bool = true
    /// The favourites scroll is a landing position, not a per-appearance
    /// behaviour — see `onAppear` below.
    @State private var didScrollToFavorites = false
    @State private var filters: [FilterSelection] = FilterSelection.defaultFilters
    @State private var plexLibrariesFilters: [GenericFilter<PlexLibrarySection>] = []

    @FocusState private var focusedField: SearchFocusFields?
    /// The last focus request answered (`SearchActivator.requestCount`). The
    /// first switch to Search asks before this screen exists to see the
    /// change, so it's caught on appear by comparing.
    @State private var answeredFocusRequest = 0
    #if targetEnvironment(macCatalyst)
    @State private var searchBarFocused: Bool = false
    #endif

    @State private var recentQueries = RecentQueriesStorage.shared
    @State private var lastNonEmptyQuery: String = ""
    /// Query+services of the last search that ran to completion; lets the
    /// `.task` below skip an identical re-search when it re-fires on
    /// navigation back from a detail.
    @State private var lastCompletedSearchKey: String?
    /// The search key the shown results answer, partial answers included.
    /// "No Results" waits for it to match: between a keystroke and its
    /// search starting, the old results and `isLoading` are both stale.
    @State private var answeredSearchKey: String?
    @State private var isLoading: Bool = false
    @State private var keyboardSelectedIndex: Int?

    private var showAlert: Bool {
#if targetEnvironment(macCatalyst)
        return false
#else
        // The window draws them in the iPad's layout (`WindowToasts`).
        return !usesPadLayout
#endif
    }

    private var suggestionCountForNav: Int {
#if targetEnvironment(macCatalyst)
        !searchCompletionTapped ? musicSearchService.suggestions.count : 0
#else
        0
#endif
    }

    /// Services enabled in Settings, in case order. Observed so disabling a
    /// service while it's selected deselects it (see validateSelectedServices).
    private var settingsEnabledServices: [MediaSearchService] {
        MediaSearchService.supported.filter { coreFeatures.isEnabled($0) }
    }

    /// The services actually searched: the stored selection minus anything
    /// disabled in Settings (validateSelectedServices prunes storage live;
    /// the read-time filter covers changes made while this screen didn't
    /// exist). TuneIn always searches alone by the selection rules.
    private var selectedSearchServices: Set<MediaSearchService> {
        guard searchSelection.primary != .tuneIn else { return [.tuneIn] }
        let enabled = searchSelection.services.filter { coreFeatures.isEnabled($0) }
        return enabled.isEmpty ? [searchSelection.primary] : Set(enabled)
    }

    /// Mirrors AppleMusicSearchScreen: a single-service Apple search without
    /// authorization renders the permissions prompt instead of results.
    private var showsApplePermissionsPrompt: Bool {
        searchSelection.primary == .apple
            && selectedSearchServices.count == 1
            && !isAppleMusicAuthorized
    }

    /// The rows actually on screen. Must apply the SAME filters the results
    /// views apply — including the Plex library filter — or the "No Results"
    /// empty state and keyboard navigation disagree with what's visible
    /// (a fully library-filtered list showed as a silent blank, and arrow
    /// keys could select rows the filter hid).
    private var currentFilteredResults: [PlayableContent] {
        guard !musicSearchService.query.isEmpty else { return [] }
        return musicSearchService.results
            .filteredByPlexLibraries(plexLibrariesFilters)
            .filtered(by: filters)
    }

    /// One key for both the search `.task(id:)` and the skip-identical-search
    /// guard, so the two can never drift. Built from the EFFECTIVE service
    /// set (not raw storage): disabling a service in Settings changes what's
    /// searched and must re-fire the task. The primary is included because it
    /// picks the single-service results view. Separators prevent key
    /// collisions between adjacent components.
    private var searchTaskKey: String {
        // Trimmed, as the search itself is: a space typed between words
        // doesn't search every service again for the same thing.
        ([offline.isActive ? "offline" : "online", musicSearchService.query.trimmingCharacters(in: .whitespaces), searchSelection.primary.rawValue]
            + selectedSearchServices.map(\.rawValue).sorted())
            .joined(separator: "|")
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
        let _ = ScrollStopLog.note("body search")

        NavigationStack(path: $router.path) {
            ScrollViewReader { proxy in
                List(selection: .constant(selectedItemID)) {
                    if offline.isActive {
                        OfflineSearchView(query: musicSearchService.query, search: offlineSearch)
                    } else {
                        SearchFilterRow(
                            primary: searchSelection.primary,
                            selectedServices: selectedSearchServices,
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
                                services: selectedSearchServices,
                                filters: $filters
                            )
                        } else {
                            SearchResultsView(
                                service: searchSelection.primary,
                                selectedServices: selectedSearchServices,
                                query: $musicSearchService.query,
                                filters: $filters,
                                plexLibrariesFilters: $plexLibrariesFilters
                            )

                            if !isLoading, answeredSearchKey == searchTaskKey, currentFilteredResults.isEmpty, !showsApplePermissionsPrompt {
                                ContentUnavailableView.search(text: musicSearchService.query)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }
                        }

                        if isLoading {
                            // maxWidth only: an unbounded-height row inside a
                            // self-sizing List cell gives UIKit an ambiguous size
                            // to resolve on every pass — loop-trap bait.
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
                .onAppear {
                    if favorites {
                        searchFieldIsPresented = false
                        Task {
                            await sonosService.getFavoriteList()
                            // Only on the first appearance. `onAppear` fires
                            // again every time the Search tab comes back, and
                            // re-running this scrolled the list down to
                            // Favourites on every return.
                            guard !didScrollToFavorites else { return }
                            didScrollToFavorites = true
                            try? await Task.sleep(for: .milliseconds(300))
                            withAnimation {
                                proxy.scrollTo("favorites", anchor: .top)
                            }
                        }
                        return
                    }
                }
                // Offline, the on-device library searched as the query
                // settles and as the songs here change.
                .task(id: offline.isActive
                      ? OfflineSearch.Key(query: musicSearchService.query.trimmingCharacters(in: .whitespacesAndNewlines), changeToken: OnDeviceLibrary.changeToken)
                      : nil) {
                    guard offline.isActive else { return }
                    await offlineSearch.run(musicSearchService.query)
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
#if targetEnvironment(macCatalyst)
                // The field is the content column's header (`searchHeader`),
                // not a navigation bar: hidden here on the root only, so a
                // pushed detail still gets its bar and back button.
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    searchHeader
                }
#endif
                .toolbar {
#if !targetEnvironment(macCatalyst)
                    // In the bar, which draws the blur under it as the list
                    // scrolls. One item: the services menu is inside the
                    // field. As a trailing item of its own, sized apart from
                    // the field, two or three services' icons pushed the row
                    // off the screen.
                    ToolbarItem(placement: .principal) {
                        searchField
                            .frame(idealWidth: 800)
                    }
#endif
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

                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task(id: searchTaskKey) {
                // Pushing a detail cancels this task and popping back restarts
                // it — same id, but `.task` re-fires on reappear. Re-running
                // the identical search re-streams providers into the list and
                // re-sorts it, visibly reshuffling results on every return.
                // If nothing changed since the last COMPLETE search, keep
                // what's on screen — but still refresh the Sonos playlists,
                // which a detail screen may have changed.
                // Offline, the rows come from the on-device library as the
                // query changes; there's no service to ask.
                let searchedKey = searchTaskKey
                guard !offline.isActive else {
                    isLoading = false
                    answeredSearchKey = searchedKey
                    return
                }
                if searchedKey == lastCompletedSearchKey, !musicSearchService.results.isEmpty {
                    isLoading = false
                    answeredSearchKey = searchedKey
                    return
                }
                isLoading = true
                if suggestion == nil {
                    searchCompletionTapped = false
                }
                // Ranking boosts items the user has played; passed per search
                // so SonosKit holds no app-side state.
                let allProvidersAnswered = await musicSearchService.search(
                    for: selectedSearchServices,
                    recentlyPlayedIDs: Set(playHistoryService.history.prefix(50).map(\.id))
                )
                // A cancelled task (query/service changed) must not clear
                // isLoading under the replacement search — that briefly
                // showed "No Results" while the real search was in flight.
                if Task.isCancelled { return }
                // A partial answer (a provider timed out) must not be
                // memoized as done — the next re-fire retries the search so
                // the missing service's rows can appear.
                lastCompletedSearchKey = allProvidersAnswered ? searchedKey : nil
                answeredSearchKey = searchedKey
                suggestion = nil
                isLoading = false
            }
            // No animation for a new result set: animating one made the List
            // diff and resize every changed row inside a single frame, 100 ms
            // on an iPhone SE each time a search answered while typing.
            .animation(.snappy, value: filters)
            .animation(.snappy, value: searchCompletionTapped)
            .modifier(DismissesSearch(showsButton: contentToAdd != nil))
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
        .presentationDragIndicator(.hidden)
        .listStyle(.plain)
        .foregroundStyle(.primary)
        .environment(router)
        .environment(musicSearchService)
        .environment(alertService)
        .modifier(DismissesSearch(added: contentToAdd?.content))
        .onChange(of: musicSearchService.query) {
            keyboardSelectedIndex = nil
            if !musicSearchService.query.isEmpty {
                lastNonEmptyQuery = musicSearchService.query
            }
        }
        // A new primary service is a different result set — drop stale results
        // immediately (a query edit deliberately keeps old results to avoid
        // flicker while typing).
        .onChange(of: searchSelection.primary) {
            musicSearchService.results = []
        }
        // Adding/removing a non-primary service does NOT clear results: the
        // merged search updates them in place, so the list doesn't flash
        // empty behind the still-open menu (which read as flicker).
        .onChange(of: searchSelection) {
            keyboardSelectedIndex = nil
        }
        // Disabling a service in Settings must also deselect it here: extras
        // are filtered out at read time, but a disabled primary stayed
        // selected (its icon lingering in the toolbar and the search still
        // querying it). task(id:) runs on appear AND when the enabled set
        // changes — the Settings sheet presents over this screen, so it fires
        // live as the user flips toggles, and the appear run catches changes
        // made while the screen didn't exist.
        .task(id: settingsEnabledServices) {
            validateSelectedServices()
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
            ScrollStopLog.note("search appeared", logNow: true)
            searchFieldIsPresented = true
            lastNonEmptyQuery = ""
            musicSearchService.query = ""
            answerFocusRequest()
        }
        .onDisappear {
            ScrollStopLog.note("search went", logNow: true)
            if !lastNonEmptyQuery.isEmpty {
                recentQueries.addOrMoveToFront(lastNonEmptyQuery)
            }
        }
        // Debug: the keyboard going down and up again while typing is the
        // field losing focus and getting it back; each is logged with what
        // came just before (`ScrollStopLog`).
        .onChange(of: focusedField) { old, new in
            if old == .search, new == nil {
                ScrollStopLog.reportRecent("search field lost focus")
            } else if new == .search {
                ScrollStopLog.note("search field focused", logNow: true)
            }
        }
        .animation(.interactiveSpring, value: focusedField)
        // Switching to the Search tab, or tapping it again, asks for the
        // field. A counter, so a second request still counts as a change.
        .onChange(of: SearchActivator.shared.requestCount) {
            answerFocusRequest()
        }
        .animation(.interactiveSpring, value: musicSearchService.suggestions)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        #if targetEnvironment(macCatalyst)
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { _ in
            searchBarFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { _ in
            searchBarFocused = false
        }
        #endif
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

    /// The search field: a glass capsule, with a ring in the accent while
    /// it has focus on the Mac, where there is no keyboard to say so.
    private var searchField: some View {
        @Bindable var musicSearchService = musicSearchService

        return HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            // Offline it searches only what's here, and says so.
            TextField(offline.isActive ? "Search Downloads" : "Search", text: $musicSearchService.query)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .search)
                .onSubmit {
                    guard let idx = keyboardSelectedIndex else { return }
                    activateSelectedItem(at: idx)
                }
            // The services being searched, at the field's end: what the
            // field searches is part of it.
            if !offline.isActive {
                MediaServiceMenu(selection: $selectionStore.selection, filters: $filters)
            }
        }
        .toolbarBackground(with: true, in: .capsule)
        #if targetEnvironment(macCatalyst)
        .overlay {
            Capsule()
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(searchBarFocused ? 1 : 0)
        }
        #endif
    }

#if targetEnvironment(macCatalyst)
    /// The Mac's search bar: the top row of the content column, in the band
    /// the sidebar's header and the queue panel's "Next Up" occupy, rather
    /// than a navigation bar of its own.
    ///
    /// It was a `.principal` toolbar item. UIKit centres that in the bar and
    /// shrinks it symmetrically to clear the trailing item, so the field
    /// started as far from the leading edge as the services menu sat from the
    /// trailing one — a gap the width of the menu, with nothing in it. As a
    /// row of its own the field starts at the same inset as the headers
    /// beside it.
    private var searchHeader: some View {
        searchField
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }
#endif

    /// Focuses the field for a request not answered yet: a switch to the
    /// Search tab, or a tap on it while it shows. Only the tab's screen
    /// (`isTab`): the tab and the Sonos Favorites sheet are both built with
    /// `favorites`, so that can't tell them apart. A beat late: focus set as
    /// the tab is still coming up doesn't take.
    private func answerFocusRequest() {
        let request = SearchActivator.shared.requestCount
        guard request != answeredFocusRequest else { return }
        answeredFocusRequest = request
        guard isTab else { return }
        ScrollStopLog.note("search focus requested", logNow: true)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            focusedField = .search
        }
    }

    /// Drops services the user disabled in Settings from the stored
    /// selection, falling back to the first enabled service so the selection
    /// is never empty.
    ///
    /// Stored only when something was dropped. A mutating call on the
    /// `@AppStorage` value saved it every time, and any UserDefaults write
    /// re-runs every `@AppStorage` view, this one included, which ran this
    /// again: on an iPhone the selection was written about 35 times a
    /// second, and Radio's list, redrawn with each write, couldn't scroll.
    private func validateSelectedServices() {
        var pruned = searchSelection
        pruned.prune(
            isEnabled: { coreFeatures.isEnabled($0) },
            fallback: settingsEnabledServices.first ?? .apple
        )
        if pruned != searchSelection {
            searchSelection = pruned
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
        case .audiobook:
            // Its page, as a tap opens; never an alarm's or a scene's music,
            // nor queued on a speaker as a song.
            guard contentToAdd?.add != true else { return }
            router.path.append(RouterDestination.audiobookDetail(content: item))
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
            let position = QueuePosition.defaultPosition(for: item.content.type, replaceQueueByDefault: UserDefaults.standard.bool(forKey: AppStorageKeys.defaultPlayAction))
            let queueSong: ((GroupRoom, QueuePosition) async throws -> Void) = { group, selectedPosition in
                QueueManager.shared.addToQueue(item: QueueItem(playableContent: item, group: group, position: selectedPosition, title: selectedPosition.title))
                Router.main.show(destination: .player(groupID: group.coordinatorID))
            }
            guard let group = selectedGroupService.group else {
                await PlayDestinationRouter.play(item, position: position, queue: queueSong)
                return
            }
            try? await queueSong(group, position)
        }
    }
}

// MARK: - Subviews

private struct SearchFilterRow: View {
    let primary: MediaSearchService
    /// Every service being searched (primary + extras): the filter chips are
    /// the union of each member's filters, and Plex's presence shows the
    /// per-library filter.
    let selectedServices: Set<MediaSearchService>
    @Binding var filters: [FilterSelection]
    @Binding var plexLibrariesFilters: [GenericFilter<PlexLibrarySection>]

    @Environment(MusicSearchService.self) private var musicSearchService

    private var searchesPlex: Bool { selectedServices.contains(.plex) }

    var body: some View {
        Group {
            if primary != .tuneIn {
                HStack(spacing: 8) {
                    FilterView(services: selectedServices, filters: $filters)
                    // Beside the chips, not laid over their trailing edge:
                    // there its glass, larger than the 24-point frame it was
                    // given, ran off the screen and covered the last chip.
                    if searchesPlex {
                        PlexLibraryFilterView(plexLibrariesFilters: $plexLibrariesFilters)
                            .task {
                                let libraries = await musicSearchService.getPlexLibraries()
                                plexLibrariesFilters = libraries.map { GenericFilter(filter: $0) }
                            }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
    }
}

private struct SearchEmptyStateView: View {
    let isAlarmSearch: Bool
    /// Every service being searched — per-service sections (Spotify browse,
    /// Apple playlists) show when their service is anywhere in the selection,
    /// not just when it's the primary.
    let services: Set<MediaSearchService>
    @Binding var filters: [FilterSelection]

    @Environment(PlayHistoryService.self) private var playHistoryService

    var body: some View {
        if !isAlarmSearch {
            RecentSearchesView()
                .listRowSeparator(.hidden)
        }

        if !playHistoryService.plays.isEmpty {
            PlayHistoryView(filters: $filters)
        }

        if !isAlarmSearch, services.contains(.spotify) {
            SpotifySearchScreen()
        }

        if !isAlarmSearch, services.contains(.apple) {
            ApplePlaylistsView()
        }
    }
}

private struct SearchResultsView: View {
    let service: MediaSearchService
    /// Every service being searched; drives the per-service extras that the
    /// single-service views carry (Plex's library selection prompt).
    let selectedServices: Set<MediaSearchService>
    @Binding var query: String
    @Binding var filters: [FilterSelection]
    @Binding var plexLibrariesFilters: [GenericFilter<PlexLibrarySection>]

    @Environment(MusicSearchService.self) private var musicSearchService

    private var isMultiService: Bool { selectedServices.count > 1 }

    var body: some View {
        if isMultiService {
            // Merged multiservice results are one ranked list; the generic
            // view renders rows for any service. The Plex library filter
            // still applies to the Plex rows — other services pass through.
            ServiceSearchView(
                results: musicSearchService.results.filteredByPlexLibraries(plexLibrariesFilters),
                filters: $filters
            )

            // Per-service extras the dedicated views carry, keyed on
            // membership rather than the primary.
            if selectedServices.contains(.plex) {
                PlexLibrarySelectionView()
            }
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
    @Binding var selection: SelectedSearchServices
    @Binding var filters: [FilterSelection]

    @Environment(Router.self) private var router
    @State private var coreFeatures = CoreFeatures.shared

    private var enabledServices: [MediaSearchService] {
        MediaSearchService.supported.filter { coreFeatures.isEnabled($0) }
    }

    /// Icons for the toolbar button: the stored selection minus disabled
    /// services (no phantom icon for a service the search skips).
    private var displayedServices: [MediaSearchService] {
        selection.services.filter { coreFeatures.isEnabled($0) }
    }

    var body: some View {
        // A native Menu (not a popover): popovers with a List/ScrollView crash
        // on Mac Catalyst. Each service is a Toggle (checkmark); a UIKit-
        // presented menu (kept open via .keepsMenuPresented + live-updated
        // with updateVisibleMenu) was tried and reverted — Catalyst renders
        // UIMenu rows as native Mac menus that ignore keepsMenuPresented and
        // draw the asset images full-size, so it only helped iOS.
        Menu {
            ForEach(enabledServices, id: \.self) { service in
                Toggle(isOn: selectionBinding(for: service)) {
                    HStack {
                        Text(service.title)
                        // The pre-tinted image: a menu row drops any
                        // foreground style and paints a template in the
                        // accent, which turned every brand mark green.
                        service.menuImage
                    }
                }
                .menuActionDismissBehavior(.disabled)
                .disabled(selection.isAtLimit && !selection.contains(service))
            }

            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                router.presentedSheet = .settings(destination: .servicePreferenceScreen)
            } label: {
                Label("Settings…", systemImage: "gear")
            }
        } label: {
            ServiceIconRow(services: displayedServices)
        }
        .accessibilityLabel("Search Services")
        .accessibilityValue(displayedServices.map(\.title).joined(separator: ", "))
    }

    private func selectionBinding(for service: MediaSearchService) -> Binding<Bool> {
        Binding(
            get: { selection.contains(service) },
            set: { _ in toggle(service) }
        )
    }

    /// The selection rules (max 3, TuneIn exclusivity, primary promotion)
    /// live in SelectedSearchServices — this just adds the UI side effects.
    private func toggle(_ service: MediaSearchService) {
        HapticManager.shared.fireHaptic(.buttonPress)
        let previousPrimary = selection.primary
        selection.toggle(service)
        if selection.primary == .tuneIn, previousPrimary != .tuneIn {
            // Type filters don't apply to a radio directory.
            for filter in filters { filter.isFiltered = false }
        }
    }
}

/// Up to three brand-colored service icons in a row — the search menu's
/// toolbar button. Deliberately plain: earlier overlapping/masked-seam
/// variants glitched and clipped while the row animated between selection
/// sizes, so the icons just sit side by side.
private struct ServiceIconRow: View {
    let services: [MediaSearchService]
    var diameter: CGFloat = 26

    private var shown: [MediaSearchService] { Array(services.prefix(3)) }

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

/// Search's way out when it's presented to pick something to add: the
/// close button, and closing once something's picked. `dismiss` is read
/// here rather than in `SearchScreen`, so a new one (a navigation stack
/// hands its views one whenever it's drawn) redraws this, not the screen.
private struct DismissesSearch: ViewModifier {
    /// The close button, inside the navigation stack.
    var showsButton: Bool?
    /// What was picked to add; a change closes Search.
    var added: PlayableContent?

    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        if let showsButton {
            content.addDismiss(override: showsButton) {
                dismiss()
            }
        } else {
            content.onChange(of: added) {
                dismiss()
            }
        }
    }
}
