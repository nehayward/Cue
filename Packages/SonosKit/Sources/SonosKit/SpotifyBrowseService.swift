import Foundation
import OrderedCollections
import MusicKit
import MusicSearchKit

@MainActor
@Observable
public final class SpotifyBrowseService {
    public static var shared = SpotifyBrowseService()

    @ObservationIgnored private let spotifyAPI = SpotifyAPI()
    public var userPlaylists: OrderedSet<PlayableContent> = []
    public var foundUser: SpotifyUser?

    public init() { }
    
    public func updateUsersRecentPlayed(userID: String, offset: Int = 0) async {
        guard let container = await spotifyAPI.userPlaylists(userID: userID) else { return }
        let newUserPlaylists = container.items.compactMap { $0?.toPlayable }
        for new in newUserPlaylists {
            userPlaylists.updateOrAppend(new)
        }
    }
    
    public func lookup(userID: String) async {
        guard let user = await spotifyAPI.lookupUser(for: userID) else {
            foundUser = nil
            return
        }
        foundUser = user
    }
}
