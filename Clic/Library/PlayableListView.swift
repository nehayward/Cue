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
    public let action: (Int) async -> [PlayableContent]

    public init(name: String, action: @escaping (Int) async -> [PlayableContent]) {
        self.name = name
        self.action = action
    }

    public var id: String { name }

    public static func == (lhs: PlayableListSort, rhs: PlayableListSort) -> Bool {
        lhs.name == rhs.name
    }
}

/// What to show in place of an empty list while its first rows are still
/// loading. A plain spinner is enough for a single request; a load that pages
/// a whole library in needs to say so, and say how far it has got.
public struct PlayableListProgress {
    public var message: String
    /// Both set for a determinate bar; `nil` leaves a spinner with the message.
    public var completed: Double?
    public var total: Double?

    public init(message: String, completed: Double? = nil, total: Double? = nil) {
        self.message = message
        self.completed = completed
        self.total = total
    }
}

struct PlayableListView: View {
    @State private var isLoading: Bool = false
    @State private var hasReachedEnd: Bool = false
    @State var items: OrderedSet<PlayableContent> = []
    @State private var showCreatePlaylist = false
    @State private var sortName: String?
    @State private var searchText = ""
    /// The query the rows on screen were loaded for, so the debounce can tell
    /// a real change from the first pass over an empty field.
    @State private var appliedQuery = ""
    /// Bumped on every reload so a load still running for the previous sort
    /// can tell that its rows are no longer wanted.
    @State private var loadGeneration = 0

    var playAllItem: PlayableContent? = nil
    var showSectionIndex: Bool = true
    /// Empty for lists with a single fixed order — no menu is shown then.
    var sortOptions: [PlayableListSort] = []
    /// Where to remember the chosen sort, so it survives leaving the screen.
    var sortStorageKey: String? = nil
    /// Supplied by lists that can search their whole source rather than the
    /// rows already loaded — filtering the loaded page would quietly miss
    /// most of the library. Called with the query and a page offset.
    var searchAction: ((String, Int) async -> [PlayableContent])? = nil
    /// Read during `body`, so a service's observable sync progress reaches the
    /// placeholder without this view knowing anything about that service.
    var progress: (() -> PlayableListProgress?)? = nil
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
        return selectedSort?.action ?? action
    }

    private var sortSelection: Binding<String> {
        Binding(
            get: { selectedSort?.name ?? "" },
            set: { name in
                guard name != selectedSort?.name else { return }
                sortName = name
                if let sortStorageKey {
                    UserDefaults.standard.set(name, forKey: Self.sortDefaultsKey(sortStorageKey))
                }
                Task { await reload() }
            }
        )
    }

    private static func sortDefaultsKey(_ key: String) -> String { "playableListSort.\(key)" }

    /// When this list is a service's playlists, the service to create a new playlist on.
    private var createPlaylistService: MusicService? {
        guard let service = items.first?.content.service,
              items.first?.content.type.isPlaylist == true,
              MusicSearchService.supportsEmptyPlaylistCreation(service) else { return nil }
        return service
    }

    var body: some View {
        List {
            PlayAllButtonView(item: playAllItem)
            contentSection
        }
        .overlay {
            // Only while there is nothing to show yet — later pages load
            // underneath the rows already on screen. Some lists (Subsonic's
            // Songs) sync before they can draw a first row, and a blank screen
            // reads as an empty library.
            if isLoading, items.isEmpty {
                loadingIndicator
            } else if items.isEmpty, !appliedQuery.isEmpty {
                ContentUnavailableView.search(text: appliedQuery)
            }
        }
        .searchableIfAvailable(text: $searchText, enabled: searchAction != nil)
        .task(id: query) {
            guard searchAction != nil, query != appliedQuery else { return }
            // Let typing settle: every keystroke would otherwise throw away a
            // load that was about to finish.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            appliedQuery = query
            await reload()
        }
        .animation(.default, value: items)
        .miniPlayerOnScrollHandler()
        .foregroundStyle(.foreground)
        .listStyle(.plain)
        .toolbar {
            if !sortOptions.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sort By", selection: sortSelection) {
                            ForEach(sortOptions) { option in
                                Text(option.name).tag(option.name)
                            }
                        }
                        .pickerStyle(.inline)
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
            if let sortStorageKey, sortName == nil {
                sortName = UserDefaults.standard.string(forKey: Self.sortDefaultsKey(sortStorageKey))
            }
            await initialLoad()
        }
    }

    @ViewBuilder
    private var loadingIndicator: some View {
        if let progress = progress?() {
            if let completed = progress.completed, let total = progress.total, total > 0 {
                ProgressView(value: min(completed, total), total: total) {
                    Text(progress.message)
                }
                .progressViewStyle(.linear)
                .padding(.horizontal, 40)
                .frame(maxWidth: 320)
            } else {
                ProgressView { Text(progress.message) }
            }
        } else {
            ProgressView()
        }
    }

    /// Re-fetch from scratch (after creating a playlist, since `items` is a
    /// snapshot, or after changing the sort).
    private func reload() async {
        loadGeneration += 1
        items.removeAll()
        hasReachedEnd = false
        // A load still running belongs to the previous order; its rows are
        // dropped by the generation check, but `initialLoad` won't start
        // while it holds `isLoading`, so wait it out rather than no-op.
        while isLoading {
            try? await Task.sleep(for: .milliseconds(50))
        }
        await initialLoad()
    }

    @ViewBuilder
    private var contentSection: some View {
        if showSectionIndex {
            ForEach(groupedItems.keys.sorted(), id: \.self) { letter in
                Section(header: Text(letter)) {
                    ForEach(groupedItems[letter] ?? []) { item in
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

        if newItems.isEmpty {
            hasReachedEnd = true
        } else {
            items.append(contentsOf: newItems)
        }
    }
}

private extension View {
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
