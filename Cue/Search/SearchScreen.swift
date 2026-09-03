import Analytics
import CloudStorage
import MusicSearchKit
import Defaults
import NukeUI
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit

struct SearchScreen: View {
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

    @AppStorage(AppStorageKeys.selectedSearchServices) private var searchSelection = SelectedSearchServices()
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined
    @AppStorage(AppStorageKeys.defaultPlayAction) private var replaceQueueByDefault: Bool = false
    var favorites: Bool = false
    /// Whether this instance draws its own search field. The tab root doesn't:
    /// `GlobalSearchField` above the `TabView` owns the query there, and a
    /// second field would fight it for focus every time the tab appeared.
    /// Everywhere else this screen is presented — the alarm picker, the
    /// inspector, pushed destinations — it still needs one.
    var showsSearchField: Bool = true
    var closeInspector: (() -> Void)? = nil

    var isAlarmSearch: Bool = false
    @State private var coreFeatures = CoreFeatures.shared
    @State private var alertService = AlertService.shared
    @State private var searchCompletionTapped: Bool = false
    @State private var suggestion: String? = nil
    /// Drives the system search field's `isPresented`, for the presentations
    /// that draw their own. Starts active so a pushed or presented search
    /// lands with the keyboard up.
    @State private var searchFieldIsPresented: Bool = true
    /// The favourites scroll is a landing position, not a per-appearance
    /// behaviour — see `onAppear` below.
    @State private var didScrollToFavorites = false
    @State private var filters: [FilterSelection] = FilterSelection.defaultFilters
    @State private var plexLibrariesFilters: [GenericFilter<PlexLibrarySection>] = []

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

    /// Services enabled in Settings, in case order. Observed so disabling a
    /// service while it's selected deselects it (see validateSelectedServices).
    private var settingsEnabledServices: [MediaSearchService] {
        MediaSearchService.allCases.filter { coreFeatures.isEnabled($0) }
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
            && appleMusicAuthorized != .authorized
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
        ([musicSearchService.query, searchSelection.primary.rawValue]
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

        NavigationStack(path: $router.path) {
            ScrollViewReader { proxy in
                List(selection: .constant(selectedItemID)) {
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

                        if !isLoading, currentFilteredResults.isEmpty, !showsApplePermissionsPrompt {
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
                        MediaServiceMenu(selection: $searchSelection, filters: $filters)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .searchableIfOwned(
                showsSearchField,
                text: $musicSearchService.query,
                isPresented: $searchFieldIsPresented
            )
            .onSubmit(of: .search) {
                guard let idx = keyboardSelectedIndex else { return }
                activateSelectedItem(at: idx)
            }
            .task(id: searchTaskKey) {
                // Pushing a detail cancels this task and popping back restarts
                // it — same id, but `.task` re-fires on reappear. Re-running
                // the identical search re-streams providers into the list and
                // re-sorts it, visibly reshuffling results on every return.
                // If nothing changed since the last COMPLETE search, keep
                // what's on screen — but still refresh the Sonos playlists,
                // which a detail screen may have changed.
                let searchedKey = searchTaskKey
                if searchedKey == lastCompletedSearchKey, !musicSearchService.results.isEmpty {
                    isLoading = false
                    playlistsContainer.playlists = await sonosService.sonosPlaylists()
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
        .animation(.interactiveSpring, value: searchFieldIsPresented)
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

    /// Drops services the user disabled in Settings from the stored
    /// selection, falling back to the first enabled service so the selection
    /// is never empty.
    private func validateSelectedServices() {
        searchSelection.prune(
            isEnabled: { coreFeatures.isEnabled($0) },
            fallback: settingsEnabledServices.first ?? .apple
        )
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
                VStack(spacing: 0) {
                    HStack {
                        FilterView(services: selectedServices, filters: $filters)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
        .overlay(alignment: .trailing) {
            if searchesPlex {
                ZStack(alignment: .trailing) {
                    // Transparent hit area to block taps below. No
                    // ignoresSafeArea here: safe-area-ignoring content inside
                    // a self-sizing List cell can trigger UIKit's layout
                    // feedback-loop trap (EXC_BREAKPOINT in
                    // _UICollectionViewFeedbackLoopDebugger on iOS 26).
                    Color.black.opacity(0.001)
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

        if !playHistoryService.history.isEmpty {
            PlayHistoryView(filters: $filters)
        }

        if !isAlarmSearch, services.contains(.spotify) {
            SpotifySearchScreen()
        }

        if !isAlarmSearch, services.contains(.apple) {
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
        MediaSearchService.allCases.filter { coreFeatures.isEnabled($0) }
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
                        service.iconForMusicService
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
        if selection.primary != previousPrimary {
            Analytics.shared.track(.selectedMusicService, with: ["MusicService": selection.primary.rawValue])
            Analytics.shared.setSelection(metadata: ["MusicService": selection.primary.rawValue])
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

private extension View {
    /// `.searchable` only where this screen owns the field. Applied
    /// unconditionally it would put a second field in the Search tab, next to
    /// the `GlobalSearchField` the `TabView` hosts.
    @ViewBuilder
    func searchableIfOwned(_ owned: Bool, text: Binding<String>, isPresented: Binding<Bool>) -> some View {
        if owned {
            searchable(text: text, isPresented: isPresented, prompt: "Search")
        } else {
            self
        }
    }
}

#Preview("Empty") {
    SearchScreen()
        .environment(Router.search)
        .forPreview()
}
