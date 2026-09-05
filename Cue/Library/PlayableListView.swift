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

    public init(
        name: String,
        ascendingLabel: String? = nil,
        descendingLabel: String? = nil,
        defaultsToDescending: Bool = false,
        action: @escaping (Int, Bool) async -> [PlayableContent]
    ) {
        self.name = name
        self.ascendingLabel = ascendingLabel
        self.descendingLabel = descendingLabel
        self.defaultsToDescending = defaultsToDescending
        self.action = action
    }

    public var isReversible: Bool { ascendingLabel != nil && descendingLabel != nil }

    public var id: String { name }

    public static func == (lhs: PlayableListSort, rhs: PlayableListSort) -> Bool {
        lhs.name == rhs.name
    }
}

struct PlayableListView: View {
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
    @State private var searchText = ""
    /// The query the rows on screen were loaded for, so the debounce can tell
    /// a real change from the first pass over an empty field.
    @State private var appliedQuery = ""
    /// Bumped on every reload so a load still running for the previous sort
    /// can tell that its rows are no longer wanted.
    @State private var loadGeneration = 0

    var title: String = ""
    var playAllItem: PlayableContent? = nil
    var showSectionIndex: Bool = true
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

        return List {
            PlayAllButtonView(item: playAllItem)
            contentSection
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

    @ViewBuilder
    private var contentSection: some View {
        if showSectionIndex {
            // Grouped once per render: `groupedItems` is computed, and
            // reading it again inside every section regrouped the whole
            // list once per letter — ~27 full passes each time a row
            // appeared and nudged the load-more check.
            let grouped = groupedItems
            ForEach(grouped.keys.sorted(), id: \.self) { letter in
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
            .onAppear {
                guard !isLoading, !hasReachedEnd,
                      let index = items.firstIndex(of: item),
                      index >= items.count - 10
                else { return }
                Task {
                    await loadMore()
                }
            }
    }

    // MARK: - Alphabetical Grouping

    private var groupedItems: [String: [PlayableContent]] {
        Dictionary(grouping: items) { item in
            guard let scalar = item.title
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .unicodeScalars
                .first,
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
            items = OrderedSet(newItems)
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
