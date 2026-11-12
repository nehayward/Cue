import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit
import MusicKit
import NukeUI
import VibesDS

/// One entry in a list's sort menu: a name and the paged loader that returns
/// rows in that order. How the order is produced is the caller's business —
/// some services sort on the server, Subsonic's songs sort a synced copy
/// locally — so the list only has to know which loader to call.
public struct PlayableListSort: Identifiable, Equatable {
    public let name: String
    /// What the two directions are called, e.g. "A – Z" / "Z – A". Both `nil`
    /// for an order that can't be flipped — a server-side one the list only
    /// pages through, where reversing would mean reversing a single page.
    public let ascendingLabel: String?
    public let descendingLabel: String?
    /// Called with a page offset and whether the order is reversed.
    public let action: (Int, Bool) async -> [PlayableContent]
    /// Whether the order reads best reversed when first chosen — newest
    /// first for a date, longest first for a length. A remembered direction
    /// still wins.
    public let defaultsToDescending: Bool
    /// What a row is filed under in the A–Z index while this order is
    /// chosen — its title, its artist — or `nil` for an order that has no
    /// index: one by date, or a server order that pages in, where jumping
    /// to a letter can only reach the pages already loaded.
    public let sectionKey: ((PlayableContent) -> String)?

    public init(
        name: String,
        ascendingLabel: String? = nil,
        descendingLabel: String? = nil,
        defaultsToDescending: Bool = false,
        sectionKey: ((PlayableContent) -> String)? = nil,
        action: @escaping (Int, Bool) async -> [PlayableContent]
    ) {
        self.name = name
        self.ascendingLabel = ascendingLabel
        self.descendingLabel = descendingLabel
        self.defaultsToDescending = defaultsToDescending
        self.sectionKey = sectionKey
        self.action = action
    }

    public var isReversible: Bool { ascendingLabel != nil && descendingLabel != nil }

    public var id: String { name }

    public static func == (lhs: PlayableListSort, rhs: PlayableListSort) -> Bool {
        lhs.name == rhs.name
    }
}

/// What a list shows, picked at the top of its sort menu under Show: all of
/// a library or only its favorites (the Apple Music library's lists). Each
/// brings its own orders, and the list remembers the pick as it does the
/// order.
public struct PlayableListFilter: Identifiable, Equatable {
    /// The pick in the menu: "All Albums", "Favorites".
    public let name: String
    public let systemImage: String
    /// The screen's title while it's picked.
    public let title: String
    public let sortOptions: [PlayableListSort]
    /// Said under "No <title>" when nothing comes back, with a button back
    /// to the first pick; nil for the plain empty list.
    public let emptyDescription: String?
    /// Only favorites: a favorite taken off from a row's menu leaves the
    /// list at once, rather than on the next read.
    public let favoritesOnly: Bool

    public init(
        name: String,
        systemImage: String,
        title: String,
        sortOptions: [PlayableListSort],
        emptyDescription: String? = nil,
        favoritesOnly: Bool = false
    ) {
        self.name = name
        self.systemImage = systemImage
        self.title = title
        self.sortOptions = sortOptions
        self.emptyDescription = emptyDescription
        self.favoritesOnly = favoritesOnly
    }

    public var id: String { name }

    public static func == (lhs: PlayableListFilter, rhs: PlayableListFilter) -> Bool {
        lhs.name == rhs.name
    }
}

/// How a list lays its rows out: as rows, or as a grid of tiles
/// (`PlayableGrid`). Remembered per list; a list not switched yet follows
/// the one key every album list once shared (`AppStorageKeys.albumsLayout`),
/// so a grid chosen before still opens as one.
enum PlayableListLayout: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .list: "List"
        case .grid: "Grid"
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        }
    }

    /// The layout a toggle switches to.
    var other: PlayableListLayout {
        self == .list ? .grid : .list
    }

    /// For switching layouts or what a list shows. None on the Mac, where an
    /// animated change of a list's rows costs ~90 MB of GPU memory for ~2 s
    /// (CLAUDE.md, "Mac GPU cost").
    static var changeAnimation: Animation? {
        #if targetEnvironment(macCatalyst)
        nil
        #else
        .smooth
        #endif
    }
}

struct PlayableListView: View {
    @Environment(FavoriteRatingCache.self) private var favoriteRatingCache

    @State private var isLoading: Bool = false
    @State private var hasReachedEnd: Bool = false
    @State var items: OrderedSet<PlayableContent> = []
    @State private var showCreatePlaylist = false
    @State private var sortName: String?
    @State private var isDescending = false
    /// Suppresses the row animation for the first fill: a local library
    /// arrives as one batch of thousands of rows, and animating that in is
    /// both pointless and expensive.
    @State private var hasLoadedOnce = false
    /// Set by the search debounce so the fill it triggers animates: rows
    /// slide out as a query narrows the list, and back in as it clears. A
    /// sort change or a first fill of thousands of rows stays instant.
    @State private var animatesNextFill = false
    @State private var searchText = ""
    /// The query the rows on screen were loaded for, so the debounce can tell
    /// a real change from the first pass over an empty field.
    @State private var appliedQuery = ""
    /// Bumped on every reload so a load still running for the previous sort
    /// can tell that its rows are no longer wanted.
    @State private var loadGeneration = 0
    /// The layout picked on this screen; before that, the one remembered.
    @State private var chosenLayout: PlayableListLayout?
    /// The Show pick, by name; nil for the first.
    @State private var filterName: String?
    /// A new sort, filter or query is being read while the old rows stay
    /// up. A whole-list sort (`LocalSorts`, MusicKit's songs by release
    /// date) can take a moment, and nothing said so.
    @State private var isReloading = false

    var title: String = ""
    var playAllItem: PlayableContent? = nil
    /// Whether a list with no sort menu buckets its rows A–Z by title. A list
    /// with a sort menu leaves that to each order's `sectionKey` instead.
    var showSectionIndex: Bool = true
    /// Whether the list can also be shown as a grid of tiles — the album
    /// and artist lists, where the art is what you scan for. Adds a list or
    /// grid button to the toolbar, beside the sort menu.
    var allowsGrid: Bool = false
    /// Where to remember rows or grid; nil shares the old key every album
    /// list had.
    var layoutStorageKey: String? = nil
    /// The layout before one is picked: a grid for Apple Music's Favorites;
    /// nil for whatever the album lists last shared.
    var defaultLayout: PlayableListLayout? = nil
    /// Empty for lists with a single fixed order — no menu is shown then.
    var sortOptions: [PlayableListSort] = []
    /// What the list can show (All, Favorites), each with its own orders,
    /// which then stand in for `sortOptions`, and its own title. Empty for
    /// most lists.
    var filterOptions: [PlayableListFilter] = []
    /// Where to remember the chosen sort and Show pick, so they survive
    /// leaving the screen.
    var sortStorageKey: String? = nil
    /// Supplied by lists whose rows come from something worth re-reading —
    /// a synced library, or a server whose library changes underneath (Plex's
    /// and Subsonic's albums and artists) — so a pull to refresh means more
    /// than reloading the first page from a copy that hasn't changed. The
    /// list reloads its first page after it.
    var refreshAction: (() async -> Void)? = nil
    /// Supplied by lists that can search their whole source rather than the
    /// rows already loaded — filtering the loaded page would quietly miss
    /// most of the library. Called with the query and a page offset.
    var searchAction: ((String, Int) async -> [PlayableContent])? = nil
    /// A line of status shown under the title while a long load runs — "11 of
    /// 10,101" as a library pages in. Read during `body`, so a service's
    /// observable progress reaches it without this view knowing anything
    /// about that service; `nil` means nothing is loading.
    var loadingStatus: (() -> String?)? = nil
    /// Read in `body`, so a source whose rows can change underneath the
    /// list — the Files index while a scan runs — makes it reload: the
    /// closure reads an observable counter, and a new value means fetch
    /// again. Nil for sources that only change when asked.
    var changeToken: (() -> Int)? = nil
    var action: ((Int) async -> ([PlayableContent]))? = nil

    /// The Show pick, the first when none is made or a remembered one is
    /// gone.
    private var selectedFilter: PlayableListFilter? {
        filterOptions.first { $0.name == filterName } ?? filterOptions.first
    }

    /// The orders on offer: the Show pick's, or the list's own.
    private var currentSortOptions: [PlayableListSort] {
        selectedFilter?.sortOptions ?? sortOptions
    }

    /// Falls back to the first option when nothing is chosen yet, or when a
    /// remembered choice no longer matches any option.
    private var selectedSort: PlayableListSort? {
        let options = currentSortOptions
        guard !options.isEmpty else { return nil }
        return options.first { $0.name == sortName } ?? options.first
    }

    /// Read straight from the defaults until one is picked here, so a list
    /// left as a grid opens as one, without a frame of rows first.
    private var layout: PlayableListLayout {
        if let chosenLayout { return chosenLayout }
        let defaults = UserDefaults.standard
        if let layoutStorageKey,
           let saved = defaults.string(forKey: Self.layoutDefaultsKey(layoutStorageKey)).flatMap(PlayableListLayout.init) {
            return saved
        }
        if let defaultLayout { return defaultLayout }
        return defaults.string(forKey: Defaults.AppStorageKeys.albumsLayout).flatMap(PlayableListLayout.init) ?? .list
    }

    private func toggleLayout() {
        let next = layout.other
        withAnimation(PlayableListLayout.changeAnimation) { chosenLayout = next }
        UserDefaults.standard.set(next.rawValue, forKey: layoutStorageKey.map(Self.layoutDefaultsKey) ?? Defaults.AppStorageKeys.albumsLayout)
    }

    /// The rows to draw: all of them, but for a favorites pick only the
    /// favorites, so a favorite taken off from its menu here goes at once,
    /// and the rows of All still up while Favorites is read don't show
    /// under its title.
    private var shownItems: [PlayableContent] {
        guard selectedFilter?.favoritesOnly == true else { return Array(items) }
        return items.filter { (favoriteRatingCache.ratings[$0.id] ?? $0.metadata?.userRating ?? 0) > 0 }
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var loader: ((Int) async -> [PlayableContent])? {
        if let searchAction, !query.isEmpty {
            let query = query
            return { offset in await searchAction(query, offset) }
        }
        if let selectedSort {
            let descending = selectedSort.isReversible && isDescending
            return { offset in await selectedSort.action(offset, descending) }
        }
        return action
    }

    private var sortSelection: Binding<String> {
        Binding(
            get: { selectedSort?.name ?? "" },
            set: { name in
                guard name != selectedSort?.name else { return }
                sortName = name
                // Each order starts in its own natural direction; the
                // direction picker is there to flip it.
                isDescending = currentSortOptions.first { $0.name == name }?.defaultsToDescending ?? false
                if let sortStorageKey {
                    UserDefaults.standard.set(name, forKey: Self.sortDefaultsKey(sortStorageKey))
                    UserDefaults.standard.set(isDescending, forKey: Self.directionDefaultsKey(sortStorageKey))
                }
                Task { await reload() }
            }
        )
    }

    private var directionSelection: Binding<Bool> {
        Binding(
            get: { isDescending },
            set: { descending in
                guard descending != isDescending else { return }
                isDescending = descending
                if let sortStorageKey {
                    UserDefaults.standard.set(descending, forKey: Self.directionDefaultsKey(sortStorageKey))
                }
                Task { await reload() }
            }
        )
    }

    /// A new Show pick keeps the order where it has one of that name, so
    /// "Date Added" stays chosen from All to Favorites; else its first.
    private var filterSelection: Binding<String> {
        Binding(
            get: { selectedFilter?.name ?? "" },
            set: { name in
                guard name != selectedFilter?.name else { return }
                withAnimation(PlayableListLayout.changeAnimation) { filterName = name }
                if let sortStorageKey {
                    UserDefaults.standard.set(name, forKey: Self.filterDefaultsKey(sortStorageKey))
                }
                if let sort = selectedSort, sort.name != sortName {
                    sortName = sort.name
                    isDescending = sort.defaultsToDescending
                }
                Task { await reload() }
            }
        )
    }

    private static func sortDefaultsKey(_ key: String) -> String { "playableListSort.\(key)" }
    private static func directionDefaultsKey(_ key: String) -> String { "playableListSort.\(key).descending" }
    private static func filterDefaultsKey(_ key: String) -> String { "playableListFilter.\(key)" }
    private static func layoutDefaultsKey(_ key: String) -> String { "playableListLayout.\(key)" }

    /// When this list is a service's playlists, the service to create a new
    /// playlist on. Every row a playlist, not just the first: Favorites, with
    /// Favorite Songs on top, offered New Playlist.
    private var createPlaylistService: MusicService? {
        guard let service = items.first?.content.service,
              items.allSatisfy(\.content.type.isPlaylist),
              MusicSearchService.supportsEmptyPlaylistCreation(service) else { return nil }
        return service
    }

    var body: some View {
        // Read here rather than inside the `.toolbar` builder. Observation
        // registers what `body` itself touches; toolbar content is built
        // separately, so a count read only in there never re-runs as it
        // climbs — the status would stay at whatever it was (usually nil,
        // since the sync starts after the first render) and never appear.
        let status = loadingStatus?()
        let token = changeToken?() ?? 0
        let shown = shownItems
        let title = selectedFilter?.title ?? self.title

        // A real container, not a `Group`: a `Group` hands its modifiers to
        // each layout, so the toolbar and tasks were each layout's own,
        // rebuilt with every switch.
        return VStack(spacing: 0) {
            // The grid only once there's something in it: loading and empty
            // read the same in either layout.
            if isGrid, !shown.isEmpty {
                gridContent(shown)
            } else {
                let sections = letterSections(shown)
                List {
                    PlayAllButtonView(item: playAllItem)
                    contentSection(shown, sections: sections)
                }
                .letterIndex(sections?.map(\.letter) ?? [])
            }
        }
        // The Show pick's title ("Favorite Albums"), else the list's.
        .navigationTitle(title)
        .overlay {
            // Only while there is nothing to show yet — later pages load
            // underneath the rows already on screen. Some lists (Subsonic's
            // Songs) sync before they can draw a first row, and a blank screen
            // reads as an empty library.
            if isLoading, shown.isEmpty {
                // How far a long load has got is in the title bar, where it
                // stays legible once rows start filling in underneath.
                ProgressView()
            } else if shown.isEmpty, !appliedQuery.isEmpty {
                ContentUnavailableView.search(text: appliedQuery)
            } else if shown.isEmpty, hasLoadedOnce, !isReloading, let filter = selectedFilter,
                      filter != filterOptions.first, let description = filter.emptyDescription {
                emptyFilter(filter, title: title, description: description)
            }
        }
        .onChange(of: token) { _, _ in
            guard hasLoadedOnce else { return }
            Task { await reload() }
        }
        .searchableIfAvailable(text: $searchText, enabled: searchAction != nil)
        .refreshableIfAvailable(refreshAction == nil ? nil : {
            await refreshAction?()
            await reload()
        })
        .task(id: query) {
            guard searchAction != nil, query != appliedQuery else { return }
            // Let typing settle: every keystroke would otherwise throw away a
            // load that was about to finish.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            appliedQuery = query
            animatesNextFill = true
            await reload()
        }
        .foregroundStyle(.foreground)
        .listStyle(.plain)
        .toolbar {
            if let status {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(title)
                            .font(.headline)
                        Text(status)
                            .font(.caption2)
                            // Fixed-width digits that roll rather than
                            // re-flow, so a climbing count reads as one number
                            // instead of a twitching line of text. Not on the
                            // Mac, where text animating as it changes draws
                            // through the GPU (CLAUDE.md, "Mac GPU cost").
                            .monospacedDigit()
                            .contentTransition(Self.rollsDigits ? .numericText() : .identity)
                            .animation(Self.rollsDigits ? .default : nil, value: status)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // A new order or pick on its way, over the rows still showing:
            // in the bar, not over the list.
            if isReloading, !shown.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    ProgressView()
                }
            }

            // One capsule: rows or grid, then the order.
            if allowsGrid || !currentSortOptions.isEmpty || !filterOptions.isEmpty {
                ToolbarItemGroup(placement: .primaryAction) {
                    if allowsGrid {
                        // One tap flips the layout. The icon is the layout a
                        // tap gives you, the way a button names what it does.
                        Button("Show as \(layout.other.label)", systemImage: layout.other.systemImage, action: toggleLayout)
                    }
                    if !currentSortOptions.isEmpty || !filterOptions.isEmpty {
                        sortMenu
                    }
                }
            }

            if createPlaylistService != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showCreatePlaylist = true
                    } label: {
                        Label("New Playlist", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .sheet(isPresented: $showCreatePlaylist, onDismiss: { Task { await reload() } }) {
            NewPlaylistView(service: createPlaylistService ?? .library)
                .withEnvironments()
        }
        .task {
            // Once per screen, not once per appearance. `.task` is cancelled
            // when a push covers the list and restarted on the way back, so
            // every return from an album fetched a fresh first page and
            // replaced the rows with it — and when that fetch came back
            // empty, or the transition cancelled it halfway, the rows were
            // gone. What was loaded stays; pull to refresh and the change
            // token still bring in anything new.
            guard !hasLoadedOnce else { return }
            if filterName == nil, !filterOptions.isEmpty, let sortStorageKey {
                filterName = UserDefaults.standard.string(forKey: Self.filterDefaultsKey(sortStorageKey))
            }
            if sortName == nil, !currentSortOptions.isEmpty {
                if let sortStorageKey {
                    sortName = UserDefaults.standard.string(forKey: Self.sortDefaultsKey(sortStorageKey))
                }
                // A remembered direction wins; otherwise the order's own.
                if let sortStorageKey,
                   UserDefaults.standard.object(forKey: Self.directionDefaultsKey(sortStorageKey)) != nil {
                    isDescending = UserDefaults.standard.bool(forKey: Self.directionDefaultsKey(sortStorageKey))
                } else {
                    isDescending = selectedSort?.defaultsToDescending ?? false
                }
            }
            await initialLoad()
        }
    }

    /// No rolling digits on the Mac (CLAUDE.md, "Mac GPU cost").
    private static var rollsDigits: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        true
        #endif
    }

    /// Show, then Sort By and the chosen order's direction. A Sort By of one
    /// (an artist's name) isn't a choice: just its order.
    private var sortMenu: some View {
        Menu {
            if !filterOptions.isEmpty {
                Picker("Show", selection: filterSelection) {
                    ForEach(filterOptions) { filter in
                        Label(filter.name, systemImage: filter.systemImage).tag(filter.name)
                    }
                }
                .pickerStyle(.inline)
            }

            if currentSortOptions.count > 1 {
                Picker("Sort By", selection: sortSelection) {
                    ForEach(currentSortOptions) { option in
                        Text(option.name).tag(option.name)
                    }
                }
                .pickerStyle(.inline)
            }

            if let sort = selectedSort,
               let ascending = sort.ascendingLabel,
               let descending = sort.descendingLabel {
                // The way the order starts on top: newest first for a date.
                Picker("Order", selection: directionSelection) {
                    if sort.defaultsToDescending {
                        Text(descending).tag(true)
                        Text(ascending).tag(false)
                    } else {
                        Text(ascending).tag(false)
                        Text(descending).tag(true)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    /// Nothing under a pick past the first (no favorites yet): what would
    /// be here, and a way back to all of it.
    private func emptyFilter(_ filter: PlayableListFilter, title: String, description: String) -> some View {
        ContentUnavailableView {
            Label("No \(title)", systemImage: filter.systemImage)
        } description: {
            Text(description)
        } actions: {
            if let first = filterOptions.first {
                Button("Show \(first.name)") {
                    filterSelection.wrappedValue = first.name
                }
            }
        }
    }

    /// Re-fetch from scratch (after creating a playlist, since `items` is a
    /// snapshot, or after changing the sort or the query).
    ///
    /// The rows on screen stay until the new ones arrive: emptying the list
    /// first turns every keystroke into a blank screen and a spinner, when
    /// what the user is doing is narrowing a list they can see.
    private func reload() async {
        isReloading = true
        defer { isReloading = false }
        loadGeneration += 1
        hasReachedEnd = false
        // A load still running belongs to the previous order; its rows are
        // dropped by the generation check, but `initialLoad` won't start
        // while it holds `isLoading`, so wait it out rather than no-op.
        // Bounded, and it stops if the view goes away mid-wait.
        var attempts = 0
        while isLoading, attempts < 200, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            attempts += 1
        }
        guard !Task.isCancelled else { return }
        await initialLoad()
    }

    private var isGrid: Bool { allowsGrid && layout == .grid }

    /// What the A–Z index files each row under, or nil for no index: the
    /// chosen order's own key when there is a sort menu, the title when the
    /// list asked for one and has no menu.
    private var sectionKey: ((PlayableContent) -> String)? {
        if let selectedSort { return selectedSort.sectionKey }
        return showSectionIndex ? { $0.title } : nil
    }

    /// The rows by letter, in the order the list runs, or nil for a list
    /// with no index. Grouped once per render, for the sections and the
    /// index alike: `groupedItems` is computed, and reading it again inside
    /// every section regrouped the whole list once per letter — ~27 full
    /// passes each time a row appeared and nudged the load-more check.
    private func letterSections(_ items: [PlayableContent]) -> [(letter: String, items: [PlayableContent])]? {
        guard let sectionKey else { return nil }
        let grouped = groupedItems(items, by: sectionKey)
        // The letters run the way the rows do, so a Z – A order keeps
        // its Z at the top rather than being re-bucketed A – Z.
        let reversed = selectedSort?.isReversible == true && isDescending
        let letters = reversed ? grouped.keys.sorted(by: >) : grouped.keys.sorted()
        return letters.map { ($0, grouped[$0] ?? []) }
    }

    @ViewBuilder
    private func contentSection(_ items: [PlayableContent], sections: [(letter: String, items: [PlayableContent])]?) -> some View {
        if let sections {
            ForEach(sections, id: \.letter) { section in
                LetterSection(letter: section.letter) {
                    ForEach(section.items) { item in
                        playableRow(item: item)
                    }
                }
            }
        } else {
            ForEach(items) { item in
                playableRow(item: item)
            }
        }
    }

    private func playableRow(item: PlayableContent) -> some View {
        PlayableContentView(item: item)
            .onAppear { loadMoreIfNeeded(after: item) }
    }

    // MARK: - Grid

    /// The same rows as tiles, as the Music app's library (`PlayableGrid`):
    /// covers with the title and artist under them, artists round. Pages in
    /// the same way as the list. No A–Z sections: a grid has no index to
    /// jump by, and the sort menu still orders it. A plain `VStack` around
    /// the grid, not a lazy one — a lazy container nested in another can
    /// cost the inner one its laziness.
    private func gridContent(_ items: [PlayableContent]) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                if playAllItem != nil {
                    PlayAllButtonView(item: playAllItem)
                }
                PlayableGrid(items: items) { item in
                    loadMoreIfNeeded(after: item)
                }
                if isLoading {
                    ProgressView()
                        .padding()
                }
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .contentMargins(.vertical, 16, for: .scrollContent)
    }

    /// Fetches the next page once `item` — one of the last ten rows — has
    /// come on screen.
    private func loadMoreIfNeeded(after item: PlayableContent) {
        guard !isLoading, !hasReachedEnd,
              let index = items.firstIndex(of: item),
              index >= items.count - 10
        else { return }
        Task {
            await loadMore()
        }
    }

    // MARK: - Alphabetical Grouping

    /// Rows are bucketed by the first letter or digit of `key`, skipping any
    /// leading punctuation or whitespace. Services sort the same way —
    /// Plex's `titleSort` drops a leading "[" — so "[Unknown Album]" arrives
    /// with the U albums; filing it under "#" by its bracket would jump it
    /// to the top of the list the moment that page loads.
    private func groupedItems(_ items: [PlayableContent], by key: (PlayableContent) -> String) -> [String: [PlayableContent]] {
        Dictionary(grouping: items) { item in
            guard let scalar = key(item)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .unicodeScalars
                .first(where: { CharacterSet.alphanumerics.contains($0) }),
                  CharacterSet.letters.contains(scalar)
            else { return "#" }

            return String(scalar).uppercased()
        }
    }

    // MARK: - Data Loading Methods

    private func initialLoad() async {
        await load(offset: 0)
    }

    private func loadMore() async {
        await load(offset: items.count)
    }

    private func load(offset: Int) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let generation = loadGeneration
        guard let newItems = await loader?(offset),
              !Task.isCancelled,
              // The sort changed while this was in flight — these rows are
              // from the old order and would interleave with the new one.
              generation == loadGeneration
        else { return }

        if offset == 0 {
            // A first page replaces what's there rather than merging into it,
            // so a narrower result really is narrower — and an empty one is an
            // answer ("no results"), not a page that failed to arrive.
            // Animated only between short lists: narrowing or clearing a
            // filter over a whole library animated the removal or insertion
            // of thousands of rows in one batch, which stalled the list.
            if animatesNextFill, items.count <= 300, newItems.count <= 300 {
                withAnimation(.default) { items = OrderedSet(newItems) }
            } else {
                items = OrderedSet(newItems)
            }
            animatesNextFill = false
            hasReachedEnd = newItems.isEmpty
        } else if newItems.isEmpty {
            hasReachedEnd = true
        } else {
            items.append(contentsOf: newItems)
        }
        hasLoadedOnce = true
    }
}

private extension View {
    /// `.refreshable` only where a refresh does something. Adding it to every
    /// list would turn a pull into "throw away the pages you scrolled for and
    /// fetch the first one again".
    @ViewBuilder
    func refreshableIfAvailable(_ action: (() async -> Void)?) -> some View {
        if let action {
            refreshable { await action() }
        } else {
            self
        }
    }

    /// `.searchable` only for the lists that can actually answer a query —
    /// a search field over a paginated list with no search loader would only
    /// look through the page in front of you.
    @ViewBuilder
    func searchableIfAvailable(text: Binding<String>, enabled: Bool) -> some View {
        if enabled {
#if os(iOS)
            // Collapses as the list scrolls — on a list this long the rows
            // matter more than a field that is one scroll away.
            searchable(text: text, placement: .navigationBarDrawer(displayMode: .automatic))
#else
            searchable(text: text)
#endif
        } else {
            self
        }
    }
}
