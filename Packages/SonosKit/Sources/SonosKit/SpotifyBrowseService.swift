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

    public func updatePlaylists(offset: Int? = nil, limit: Int = 5) async {
        let offset = offset ?? playlists.count
        guard let container = await spotifyAPI.userPlaylists(offset: offset, limit: limit) else {
            return
        }
        
        let newUserPlaylists = container.items.compactMap { $0?.toPlayable }
        // Merge in place: keep already-loaded items where they are and append genuinely new ones.
        // (A reload of the first page used to reinsert at the front and prune, which made the
        // browse preview resort every time the section reappeared.) Removals are handled by the
        // pull-to-refresh, which clears the set before reloading.
        for new in newUserPlaylists {
            playlists.updateOrAppend(new)
        }
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
        // Merge in place: keep already-loaded albums where they are and append genuinely new ones.
        // (A reload of the first page used to reinsert at the front and prune, which made the
        // browse preview resort every time the section reappeared and could drop albums the user
        // had already paged in.) Removals are handled by the pull-to-refresh, which clears the set
        // before reloading.
        for new in newAlbums {
            albums.updateOrAppend(new)
        }
    }

    public func updateSongs(offset: Int? = nil, limit: Int = 25) async {
        let offset = offset ?? tracks.count
        guard let container = await spotifyAPI.userTracks(offset: offset, limit: limit) else { return }
        let newTracks = container.items.compactMap { $0?.track.toPlayable }
        // Merge in place: keep already-loaded songs where they are and append genuinely new ones.
        // (A reload of the first page used to reinsert at the front and prune, which made the
        // browse preview resort every time the section reappeared.) Removals are handled by the
        // pull-to-refresh, which clears the set before reloading.
        for new in newTracks {
            tracks.updateOrAppend(new)
        }
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
