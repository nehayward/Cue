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
        let playlists = await plexAPI.playlists()
        let newUserPlaylists = playlists.map(\.toPlayable)
        for newUserPlaylist in newUserPlaylists {
            userPlaylists.updateOrAppend(newUserPlaylist)
        }
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

