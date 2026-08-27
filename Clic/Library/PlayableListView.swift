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
struct PlayableListSort: Identifiable, Equatable {
    let name: String
    let action: (Int) async -> [PlayableContent]

    var id: String { name }

    static func == (lhs: PlayableListSort, rhs: PlayableListSort) -> Bool {
        lhs.name == rhs.name
    }
}

struct PlayableListView: View {
    @State private var isLoading: Bool = false
    @State private var hasReachedEnd: Bool = false
    @State var items: OrderedSet<PlayableContent> = []
    @State private var showCreatePlaylist = false
    @State private var sortName: String?
    /// Bumped on every reload so a load still running for the previous sort
    /// can tell that its rows are no longer wanted.
    @State private var loadGeneration = 0

    var playAllItem: PlayableContent? = nil
    var showSectionIndex: Bool = true
    /// Empty for lists with a single fixed order — no menu is shown then.
    var sortOptions: [PlayableListSort] = []
    /// Where to remember the chosen sort, so it survives leaving the screen.
    var sortStorageKey: String? = nil
    var action: ((Int) async -> ([PlayableContent]))? = nil

    /// Falls back to the first option when nothing is chosen yet, or when a
    /// remembered choice no longer matches any option.
    private var selectedSort: PlayableListSort? {
        guard !sortOptions.isEmpty else { return nil }
        return sortOptions.first { $0.name == sortName } ?? sortOptions.first
    }

    private var loader: ((Int) async -> [PlayableContent])? {
        selectedSort?.action ?? action
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
                ProgressView()
            }
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
