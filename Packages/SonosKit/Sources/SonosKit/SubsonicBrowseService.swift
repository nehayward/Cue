import Foundation
import MusicSearchKit
import OrderedCollections

@MainActor
@Observable
public final class SubsonicBrowseService {
    public static let shared = SubsonicBrowseService()

    public var userPlaylists: OrderedSet<PlayableContent> = []
    public var recentAlbums: [PlayableContent] = []
    public var isLoading = false
    public var isAuthenticated = false

    private let musicSearchService = MusicSearchService.shared

    private init() {}

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        isAuthenticated = musicSearchService.isSubsonicConfigured
        guard isAuthenticated else { return }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [self] in
                let playlists = await self.musicSearchService.subsonicUserPlaylists()
                await MainActor.run { self.userPlaylists = OrderedSet(playlists) }
            }
            group.addTask { [self] in
                let albums = await self.musicSearchService.subsonicRecentAlbums()
                await MainActor.run { self.recentAlbums = albums }
            }
        }
    }

    public func refresh() async {
        userPlaylists = []
        recentAlbums = []
        isAuthenticated = false
        await load()
    }
}
