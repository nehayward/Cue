import Foundation
import MusicSearchKit
import OrderedCollections

@MainActor
@Observable
public final class DeezerBrowseService {
    public static let shared = DeezerBrowseService()

    public var userPlaylists: OrderedSet<PlayableContent> = []
    public var recentlyPlayed: [PlayableContent] = []
    public var isLoading = false
    public var isAuthenticated = false

    private let musicSearchService = MusicSearchService.shared

    private init() {}

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        isAuthenticated = await musicSearchService.isDeezerAuthenticated
        guard isAuthenticated else { return }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [self] in
                let playlists = await self.musicSearchService.deezerUserPlaylists()
                await MainActor.run { self.userPlaylists = OrderedSet(playlists) }
            }
            group.addTask { [self] in
                let history = await self.musicSearchService.deezerUserHistory()
                await MainActor.run { self.recentlyPlayed = history }
            }
        }
    }

    public func refresh() async {
        userPlaylists = []
        recentlyPlayed = []
        isAuthenticated = false
        await load()
    }
}
