import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit
import MusicKit
import NukeUI
import VibesDS

struct PlayableListView: View {
    @State private var isLoading: Bool = false
    @State private var hasReachedEnd: Bool = false
    @State var items: OrderedSet<PlayableContent> = []

    var playAllItem: PlayableContent? = nil
    var showSectionIndex: Bool = true
    var action: ((Int) async -> ([PlayableContent]))? = nil

    var body: some View {
        List {
            PlayAllButtonView(item: playAllItem)
            contentSection
        }
        .miniPlayerOnScrollHandler()
        .foregroundStyle(.foreground)
        .listStyle(.plain)
        .task {
            await initialLoad()
        }
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
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let newItems = await action?(0), !Task.isCancelled else { return }

        if newItems.isEmpty {
            hasReachedEnd = true
        } else {
            items.append(contentsOf: newItems)
        }
    }

    private func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let newItems = await action?(items.count), !Task.isCancelled else { return }

        if newItems.isEmpty {
            hasReachedEnd = true
        } else {
            items.append(contentsOf: newItems)
        }
    }
}
