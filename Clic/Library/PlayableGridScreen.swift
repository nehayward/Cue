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
    @Binding var items: OrderedSet<PlayableContent>

    var action: ((Int) async -> ())? = nil
    private let adaptiveColumn = [GridItem(.adaptive(minimum: 120, maximum: 200), spacing: 16), GridItem(.adaptive(minimum: 120, maximum: 200), spacing: 16)]

    @Namespace private var zoom

    /// Zoom-from-card is being trialed on the Plex playlists grid only —
    /// widen to other grids later if it feels right.
    private var zoomNamespaceIfEnabled: Namespace.ID? {
        guard let first = items.first?.content,
              first.service == .plex, first.type.isPlaylist else { return nil }
        return zoom
    }

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
                    PlayableCardView(item: item, zoomNamespace: zoomNamespaceIfEnabled)
                        .task {
                            if items.firstIndex(of: item) ?? 0 >= items.count - 1 {
                                Task {
                                    await action?(items.count)
                                }
                            }
                        }
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
