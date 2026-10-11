import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit
import MusicKit
import NukeUI
import VibesDS

/// The orders a grid offers, and where the chosen one lives. The grid draws
/// a service's own list, which other screens show too, so the order is the
/// service's: the menu reads and sets it through these bindings, and the
/// grid fetches again in the new order.
public struct PlayableGridSort {
    struct Option: Identifiable {
        let name: String
        /// What the two directions are called, the natural one first —
        /// "A – Z" / "Z – A", "Newest First" / "Oldest First".
        let ascendingLabel: String
        let descendingLabel: String

        var id: String { name }
    }

    let options: [Option]
    /// The chosen option's name.
    let selection: Binding<String>
    /// Whether the chosen option runs against its natural direction.
    let isReversed: Binding<Bool>
}

/// The grid's sort menu. Its own view, so the choice it reads from the
/// service is tracked by its own body: reads made in a toolbar's builder
/// aren't, and the checkmarks would lag behind a pick.
private struct PlayableGridSortMenu: View {
    let sort: PlayableGridSort
    /// Called after a pick changes the order.
    let onChange: () -> Void

    var body: some View {
        let selected = sort.options.first { $0.name == sort.selection.wrappedValue }

        Menu {
            Picker("Sort By", selection: changing(sort.selection)) {
                ForEach(sort.options) { option in
                    Text(option.name).tag(option.name)
                }
            }
            .pickerStyle(.inline)

            if let selected {
                Picker("Order", selection: changing(sort.isReversed)) {
                    Text(selected.ascendingLabel).tag(false)
                    Text(selected.descendingLabel).tag(true)
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    /// `binding`, calling `onChange` when a pick really changes it.
    private func changing<Value: Equatable>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(
            get: { binding.wrappedValue },
            set: { value in
                guard value != binding.wrappedValue else { return }
                binding.wrappedValue = value
                onChange()
            }
        )
    }
}

struct PlayableGridScreen: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(LibraryBrowseService.self) var browseService
    @Environment(Router.self) private var router

    @State private var isLoading: Bool = false
    /// A page is on its way; no other is asked for meanwhile.
    @State private var isLoadingMore = false
    /// The last page added nothing: there's no more to ask for until a refresh.
    @State private var reachedEnd = false
    @Binding var items: OrderedSet<PlayableContent>

    /// Nil for a grid with a single fixed order — no menu is shown then.
    var sort: PlayableGridSort? = nil
    var action: ((Int) async -> ())? = nil
    private let adaptiveColumn = [GridItem(.adaptive(minimum: 120, maximum: 200), spacing: 16), GridItem(.adaptive(minimum: 120, maximum: 200), spacing: 16)]

    /// When this grid is showing a service's playlists, the service to create a new playlist on —
    /// only services that can create an empty playlist.
    private var createPlaylistService: MusicService? {
        guard let service = items.first?.content.service,
              items.first?.content.type.isPlaylist == true,
              MusicSearchService.supportsEmptyPlaylistCreation(service) else { return nil }
        return service
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: adaptiveColumn, spacing: 16) {
                ForEach(items) { item in
                    PlayableCardView(item: item)
                        .onAppear { loadMoreIfNeeded(after: item) }
                }
            }

            // TODO: Improve
            if items.isEmpty, !isLoading {
                ContentUnavailableView {
                    Text("No Items")
                }
            }
        }
        .refreshable {
            reachedEnd = false
            await action?(0)
        }
        .miniPlayerOnScrollHandler()
        .overlay {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .animation(.interactiveSpring, value: items)
        .toolbar {
            if action != nil {
                // An explicit refresh that works on every platform (pull-to-refresh isn't available
                // on Mac/Catalyst), so deletes/creates made elsewhere can be pulled in.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        reachedEnd = false
                        Task { await action?(0) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Refresh")
                }
            }
            if let sort {
                ToolbarItem(placement: .primaryAction) {
                    // The tiles already there stay until the new order
                    // arrives, then move into it, rather than the grid
                    // going blank behind a spinner.
                    PlayableGridSortMenu(sort: sort) {
                        reachedEnd = false
                        Task { await action?(0) }
                    }
                }
            }
            if let service = createPlaylistService {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        router.presentedSheet = .newPlaylist(service: service)
                    } label: {
                        Label("New Playlist", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .task {
            isLoading = true
            await action?(0)
            isLoading = false
        }
    }
}

extension PlayableGridScreen {
    /// Asks for the next page when the last tile appears, one page at a
    /// time: each tile used to ask as it appeared, with nothing stopping a
    /// second request for the same page while the first was on its way.
    fileprivate func loadMoreIfNeeded(after item: PlayableContent) {
        guard !isLoadingMore, !reachedEnd, items.last == item else { return }
        isLoadingMore = true
        let countBefore = items.count
        Task {
            await action?(items.count)
            reachedEnd = items.count == countBefore
            isLoadingMore = false
        }
    }
}
