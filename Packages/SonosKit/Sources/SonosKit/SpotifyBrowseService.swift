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
        if offset == 0, !playlists.isEmpty {
            for new in newUserPlaylists {
                playlists.insert(new, at: 0)
            }
            
            for playlist in playlists.prefix(10) {
                if !newUserPlaylists.contains(playlist) {
                    playlists.remove(playlist)
                }
            }
        } else {
            for new in newUserPlaylists {
                playlists.updateOrAppend(new)
            }
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

        if offset == 0, !albums.isEmpty {
            // Refresh of the first page: surface newly-added albums at the top and reconcile
            // removals — but only within the window we actually re-fetched. Reconciling against
            // `prefix(10)` while fetching a smaller page (the album list view fetches `limit: 5`)
            // deleted albums the user had already paged in, making the list shrink and reshuffle
            // every time they reopened it or segued back to it.
            for new in newAlbums {
                albums.insert(new, at: 0)
            }

            for album in albums.prefix(newAlbums.count) {
                if !newAlbums.contains(album) {
                    albums.remove(album)
                }
            }
        } else {
            for new in newAlbums {
                albums.updateOrAppend(new)
            }
        }
    }

    public func updateSongs(offset: Int? = nil, limit: Int = 25) async {
        let offset = offset ?? tracks.count
        guard let container = await spotifyAPI.userTracks(offset: offset, limit: limit) else { return }
        let newTracks = container.items.compactMap { $0?.track.toPlayable }
        if offset == 0, !tracks.isEmpty, !newTracks.isEmpty {
            for new in newTracks {
                tracks.insert(new, at: 0)
            }
            
            for track in tracks.prefix(10) {
                if !newTracks.contains(track) {
                    tracks.remove(track)
                }
            }
        } else {
            for new in newTracks {
                tracks.updateOrAppend(new)
            }
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
