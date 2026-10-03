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

/// How a list lays its rows out: as rows, or as a grid of artwork tiles.
/// Stored under one key for every album list, so the choice follows the
/// user from one provider's Albums to the next.
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
}

struct PlayableListView: View {
    @AppStorage(Defaults.AppStorageKeys.albumsLayout) private var layout: PlayableListLayout = .list
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.displayScale) private var displayScale

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

    var title: String = ""
    var playAllItem: PlayableContent? = nil
    /// Whether a list with no sort menu buckets its rows A–Z by title. A list
    /// with a sort menu leaves that to each order's `sectionKey` instead.
    var showSectionIndex: Bool = true
    /// Whether the list can also be shown as a grid of artwork tiles — the
    /// album lists, where the art is what you scan for. Adds a View toggle
    /// to the toolbar; the choice is shared across every list that offers it.
    var allowsGrid: Bool = false
    /// Empty for lists with a single fixed order — no menu is shown then.
    var sortOptions: [PlayableListSort] = []
    /// Where to remember the chosen sort, so it survives leaving the screen.
    var sortStorageKey: String? = nil
    /// Supplied by lists whose rows come from something worth re-reading —
    /// a synced library — so a pull to refresh means more than reloading the
    /// first page from a copy that hasn't changed.
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

    /// Falls back to the first option when nothing is chosen yet, or when a
    /// remembered choice no longer matches any option.
    private var selectedSort: PlayableListSort? {
        guard !sortOptions.isEmpty else { return nil }
        return sortOptions.first { $0.name == sortName } ?? sortOptions.first
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
                isDescending = sortOptions.first { $0.name == name }?.defaultsToDescending ?? false
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

    private static func sortDefaultsKey(_ key: String) -> String { "playableListSort.\(key)" }
    private static func directionDefaultsKey(_ key: String) -> String { "playableListSort.\(key).descending" }

    /// When this list is a service's playlists, the service to create a new playlist on.
    private var createPlaylistService: MusicService? {
        guard let service = items.first?.content.service,
              items.first?.content.type.isPlaylist == true,
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

        return Group {
            if isGrid {
                gridContent
            } else {
                List {
                    PlayAllButtonView(item: playAllItem)
                    contentSection
                }
            }
        }
        .overlay {
            // Only while there is nothing to show yet — later pages load
            // underneath the rows already on screen. Some lists (Subsonic's
            // Songs) sync before they can draw a first row, and a blank screen
            // reads as an empty library.
            if isLoading, items.isEmpty {
                // How far a long load has got is in the title bar, where it
                // stays legible once rows start filling in underneath.
                ProgressView()
            } else if items.isEmpty, !appliedQuery.isEmpty {
                ContentUnavailableView.search(text: appliedQuery)
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
        .miniPlayerOnScrollHandler()
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
                            // instead of a twitching line of text.
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.default, value: status)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if allowsGrid {
                // One tap flips the layout. The icon is the layout a tap
                // gives you, the way a button names what it does.
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        layout = layout.other
                    } label: {
                        Label("Show as \(layout.other.label)", systemImage: layout.other.systemImage)
                    }
                }
            }

            if !sortOptions.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sort By", selection: sortSelection) {
                            ForEach(sortOptions) { option in
                                Text(option.name).tag(option.name)
                            }
                        }
                        .pickerStyle(.inline)

                        if let sort = selectedSort,
                           let ascending = sort.ascendingLabel,
                           let descending = sort.descendingLabel {
                            Picker("Order", selection: directionSelection) {
                                Text(ascending).tag(false)
                                Text(descending).tag(true)
                            }
                            .pickerStyle(.inline)
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
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
            if sortName == nil, !sortOptions.isEmpty {
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

    /// Re-fetch from scratch (after creating a playlist, since `items` is a
    /// snapshot, or after changing the sort or the query).
    ///
    /// The rows on screen stay until the new ones arrive: emptying the list
    /// first turns every keystroke into a blank screen and a spinner, when
    /// what the user is doing is narrowing a list they can see.
    private func reload() async {
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

    @ViewBuilder
    private var contentSection: some View {
        if let sectionKey {
            // Grouped once per render: `groupedItems` is computed, and
            // reading it again inside every section regrouped the whole
            // list once per letter — ~27 full passes each time a row
            // appeared and nudged the load-more check.
            let grouped = groupedItems(by: sectionKey)
            // The letters run the way the rows do, so a Z – A order keeps
            // its Z at the top rather than being re-bucketed A – Z.
            let reversed = selectedSort?.isReversible == true && isDescending
            let letters = reversed ? grouped.keys.sorted(by: >) : grouped.keys.sorted()
            ForEach(letters, id: \.self) { letter in
                Section(header: Text(letter)) {
                    ForEach(grouped[letter] ?? []) { item in
                        playableRow(item: item)
                    }
                }
                .sectionIndex(letter)
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

    /// As many tiles as fit, each at least this wide: three across a phone,
    /// more as the width grows, stretching to fill the row. The layout
    /// adapts to the window on its own — nothing is measured.
    private static let gridColumns = [GridItem(.adaptive(minimum: 128, maximum: 220), spacing: 0)]

    /// The size every tile asks its cover for — one tier per device class,
    /// not the tile's measured width. A phone's tiles are never wider than
    /// about 145pt, an iPad's or a Mac's never wider than the column
    /// maximum, so a cover decoded at the tier is sharp in any tile the
    /// layout produces, while a window resize only re-lays out: the same
    /// decoded bitmaps, scaled by the GPU, never fetched or decoded again.
    /// One request per album per class also means the cache is hit on the
    /// way back, and by any other grid showing the same album.
    ///
    /// The artwork view decodes at three pixels per point, a phone's
    /// density; the tier is scaled down for the screen at hand so a 2x Mac
    /// or iPad decodes 440px covers, not 660px, and holds half the memory
    /// for each.
    private var gridArtworkSize: Double {
        let points: Double = sizeClass == .compact ? 150 : 220
        return points * min(displayScale, 3) / 3
    }

    /// The same rows as a wall of covers: square tiles that touch, edge to
    /// edge, with nothing written under them — the art is what you scan
    /// for, and the title is a tap away. Pages in the same way as the
    /// list. No A–Z sections: a grid has no index to jump by, and the sort
    /// menu still orders it. A plain `VStack` around the grid, not a lazy
    /// one — a lazy container nested in another can cost the inner one
    /// its laziness.
    private var gridContent: some View {
        let artworkSize = gridArtworkSize
        return ScrollView {
            VStack(spacing: 0) {
                if playAllItem != nil {
                    PlayAllButtonView(item: playAllItem)
                        .padding(16)
                }
                LazyVGrid(columns: Self.gridColumns, spacing: 0) {
                    ForEach(items) { item in
                        gridTile(item, artworkSize: artworkSize)
                            .onAppear { loadMoreIfNeeded(after: item) }
                    }
                }
            }
        }
    }

    /// One cover. With a zoom namespace from the root, the tile is what the
    /// album screen zooms out of; without one it pushes plainly. Not on
    /// Catalyst, where the zoom transition doesn't animate and a matched
    /// source on every tile would be bookkeeping for nothing.
    @ViewBuilder
    private func gridTile(_ item: PlayableContent, artworkSize: Double) -> some View {
#if targetEnvironment(macCatalyst)
        PlayableCardView(item: item, artworkOnly: true, artworkSize: artworkSize)
#else
        if let zoomNamespace {
            PlayableCardView(item: item, artworkOnly: true, artworkSize: artworkSize, zoomSource: .album(item.id))
                .zoomSource(.album(item.id), in: zoomNamespace)
        } else {
            PlayableCardView(item: item, artworkOnly: true, artworkSize: artworkSize)
        }
#endif
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
    private func groupedItems(by key: (PlayableContent) -> String) -> [String: [PlayableContent]] {
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
