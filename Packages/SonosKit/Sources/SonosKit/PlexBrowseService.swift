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
        let refreshed = OrderedSet(await plexAPI.playlists().map(\.toPlayable))
        // Replace wholesale so deleted playlists disappear and re-created ones reappear. Keep the
        // current list on an empty/failed fetch (auth blip) rather than flashing it away, and skip
        // a no-op assignment so a reload triggered from the grid can't loop.
        guard !refreshed.isEmpty, refreshed != userPlaylists else { return }
        userPlaylists = refreshed
    }
    
    public func artists(offset: Int? = 0) async -> [PlayableContent]  {
        let artists = await plexAPI.artists(offset: offset ?? 0)
        return artists.compactMap(\.toPlayable)
    }
    
    public func updateUserAlbums(offset: Int? = 0) async -> [PlayableContent]  {
        let albums = await plexAPI.albums(offset: offset ?? 0)
        let newUserAlbums = albums.compactMap(\.toPlayable)
        return newUserAlbums
    }
    
    public func songs(offset: Int? = 0) async -> [PlayableContent]  {
        let songs = await plexAPI.songs(offset: offset ?? 0)
        return songs.compactMap(\.toPlayable)
    }
}

