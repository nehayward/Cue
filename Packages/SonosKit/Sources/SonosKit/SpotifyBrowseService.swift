import Foundation
import OrderedCollections
import MusicKit
import MusicSearchKit

@MainActor
@Observable
public final class SpotifyBrowseService {
    public static var shared = SpotifyBrowseService()

    @ObservationIgnored private let spotifyAPI = SpotifyAPI(tokenRefreshHandler: KeychainTokenRefreshHandler.shared)
    @ObservationIgnored private let spotifyLookupAPI = SpotifySonosAPI(tokenRefreshHandler: KeychainTokenRefreshHandler.shared)

    public var tracks: OrderedSet<PlayableContent> = []
    public var albums: OrderedSet<PlayableContent> = []
    public var playlists: OrderedSet<PlayableContent> = []
    public var userPlaylists: OrderedSet<PlayableContent> = []
    public var foundUser: SpotifyUser?

    public init() { }

    /// Merges a freshly-fetched page into a browse collection.
    ///
    /// For the first page (`isFirstPage`), the collection is rebuilt as the fetched page followed
    /// by any previously-loaded items that fell outside it. Spotify returns saved items
    /// newest-first, so a newly-added item lands at the top — but re-fetching the same first page
    /// is a no-op, so revisiting a browse section never reshuffles what's already there. For
    /// later pages, the new items are simply appended. Removals are reconciled by the
    /// pull-to-refresh, which clears the collection before reloading.
    private func merge(_ newItems: [PlayableContent], into collection: inout OrderedSet<PlayableContent>, isFirstPage: Bool) {
        if isFirstPage {
            let fetched = Set(newItems)
            let retained = collection.filter { !fetched.contains($0) }
            collection = OrderedSet(newItems + retained)
        } else {
            for item in newItems {
                collection.updateOrAppend(item)
            }
        }
    }

    public func updatePlaylists(offset: Int? = nil, limit: Int = 5) async {
        let offset = offset ?? playlists.count
        guard let container = await spotifyAPI.userPlaylists(offset: offset, limit: limit) else {
            return
        }
        
        let newUserPlaylists = container.items.compactMap { $0?.toPlayable }
        merge(newUserPlaylists, into: &playlists, isFirstPage: offset == 0)
    }
    
    public func userAlbums(offset: Int? = nil, limit: Int = 5) async {
        // Fall back to the current album count so an offset-less call continues paging from the
        // end of what's loaded. (Previously this used `playlists.count`, which made album
        // pagination start at the wrong place whenever the two lists were different sizes.)
        let offset = offset ?? albums.count
        guard let container = await spotifyAPI.userAlbums(offset: offset, limit: limit) else {
            return
        }
        let newAlbums = container.items.compactMap { $0?.album.toPlayable }
        merge(newAlbums, into: &albums, isFirstPage: offset == 0)
    }

    public func updateSongs(offset: Int? = nil, limit: Int = 25) async {
        let offset = offset ?? tracks.count
        guard let container = await spotifyAPI.userTracks(offset: offset, limit: limit) else { return }
        let newTracks = container.items.compactMap { $0?.track.toPlayable }
        merge(newTracks, into: &tracks, isFirstPage: offset == 0)
    }
    
    /// Updates both playlists and songs concurrently
    public func updatePlaylistsAndSongs(offset: Int? = nil) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.updatePlaylists(offset: offset, limit: 10)
            }

            group.addTask {
                await self.updateSongs(offset: offset, limit: 10)
            }

            group.addTask {
                await self.userAlbums(offset: offset, limit: 10)
            }
        }
    }

    @available(*, deprecated, message: "Use updateAllPlaylistsAndRecentPlayed(userID:) instead")
    public func updateUsersRecentPlayed(userID: String, offset: Int = 0) async {
        guard let container = await spotifyAPI.userPlaylists(userID: userID) else { return }
        let newUserPlaylists = container.items.compactMap { $0?.toPlayable }
        for new in newUserPlaylists {
            userPlaylists.updateOrAppend(new)
        }
    }

    @available(*, deprecated, message: "User lookup is now handled internally; no need to call this directly")
    public func lookup(userID: String) async {
        guard let user = await spotifyAPI.lookupUser(for: userID) else {
            foundUser = nil
            return
        }
        foundUser = user
    }
}
