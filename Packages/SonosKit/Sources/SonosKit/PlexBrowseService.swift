import Foundation
import OrderedCollections
import MusicKit
import MusicSearchKit


@Observable
public final class PlexBrowseService {
    public static var shared = PlexBrowseService()
    @ObservationIgnored private let plexAPI = PlexAPI.shared

    public var userAlbums: OrderedSet<PlayableContent> = []
    public var userPlaylists: OrderedSet<PlayableContent> = []

    public init() { }

    public func updateUserPlaylists(offset: Int? = 0) async {
        // Merge in the server's playlists (additive) so a just-created playlist is never dropped —
        // Plex can briefly omit a brand-new empty playlist from this list. Deletions are reflected
        // explicitly by the delete flow (`removeUserPlaylist`), not by clearing here.
        for playlist in await plexAPI.playlists().map(\.toPlayable) {
            userPlaylists.updateOrAppend(playlist)
        }
    }
    
    public func artists(offset: Int? = 0) async -> [PlayableContent]  {
        let artists = await plexAPI.artists(offset: offset ?? 0)
        return artists.compactMap(\.toPlayable)
    }
    
    /// A page of albums in the requested order. As with songs, Plex sorts on
    /// the server, so the order (reversed included) holds across every page.
    public func updateUserAlbums(offset: Int? = 0, sort: PlexAlbumSort = .title, reversed: Bool = false) async -> [PlayableContent]  {
        let albums = await plexAPI.albums(sort: sort, reversed: reversed, offset: offset ?? 0)
        let newUserAlbums = albums.compactMap(\.toPlayable)
        return newUserAlbums
    }
    
    /// A page of songs in the requested order. Plex sorts on the server, so
    /// there is nothing to sync and nothing to re-sort — the order (reversed
    /// included) holds across every page.
    public func songs(offset: Int? = 0, sort: PlexSongSort = .title, reversed: Bool = false) async -> [PlayableContent]  {
        let songs = await plexAPI.songs(sort: sort, reversed: reversed, offset: offset ?? 0)
        return songs.compactMap(\.toPlayable)
    }
}

