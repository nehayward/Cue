import Foundation
import OrderedCollections
import MusicKit
import MusicSearchKit

@MainActor
@Observable
public final class PlexBrowseService {
    public static var shared = PlexBrowseService()
    @ObservationIgnored private let plexAPI = PlexAPI()

    public var userPlaylists: OrderedSet<PlayableContent> = []

    public init() { }

    public func updateUserPlaylists(offset: Int? = 0) async {
        let playlists = await plexAPI.playlists()
        let newUserPlaylists = playlists.map(\.toPlayable)
        for newUserPlaylist in newUserPlaylists {
            userPlaylists.updateOrAppend(newUserPlaylist)
        }
    }
}

