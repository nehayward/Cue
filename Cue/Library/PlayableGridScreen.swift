import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit
import MusicKit
import NukeUI
import VibesDS

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
