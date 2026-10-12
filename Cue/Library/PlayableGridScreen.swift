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
    /// The sort menu's choice, copied from `sort` into the grid's own state.
    /// The menu's checkmarks follow state the view owns, as
    /// `PlayableListView`'s do; bound straight to the service, the order
    /// changed but the checkmarks stayed on the first pick.
    @State private var sortName = ""
    @State private var isSortReversed = false

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
        // Read in `body` itself, so a pick runs it again: what only the
        // toolbar's builder reads doesn't, and the menu would keep drawing
        // the old checkmarks.
        let _ = (sortName, isSortReversed)

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
                    sortMenu(sort)
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
            if let sort {
                sortName = sort.selection.wrappedValue
                isSortReversed = sort.isReversed.wrappedValue
            }
            isLoading = true
            await action?(0)
            isLoading = false
        }
    }
}

extension PlayableGridScreen {
    /// Sort By and, for the chosen order, its direction — the same menu as
    /// `PlayableListView`'s. A pick sets the service's order and fetches
    /// again.
    fileprivate func sortMenu(_ sort: PlayableGridSort) -> some View {
        Menu {
            Picker("Sort By", selection: Binding(
                get: { sortName },
                set: { name in
                    guard name != sortName else { return }
                    sort.selection.wrappedValue = name
                    sortName = name
                    // The service starts each order in its own direction.
                    isSortReversed = sort.isReversed.wrappedValue
                    reloadInNewOrder()
                }
            )) {
                ForEach(sort.options) { option in
                    Text(option.name).tag(option.name)
                }
            }
            .pickerStyle(.inline)

            if let option = sort.options.first(where: { $0.name == sortName }) {
                Picker("Order", selection: Binding(
                    get: { isSortReversed },
                    set: { reversed in
                        guard reversed != isSortReversed else { return }
                        sort.isReversed.wrappedValue = reversed
                        isSortReversed = reversed
                        reloadInNewOrder()
                    }
                )) {
                    Text(option.ascendingLabel).tag(false)
                    Text(option.descendingLabel).tag(true)
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    /// The tiles already there stay until the new order arrives, then move
    /// into it, rather than the grid going blank behind a spinner.
    fileprivate func reloadInNewOrder() {
        reachedEnd = false
        Task { await action?(0) }
    }

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
