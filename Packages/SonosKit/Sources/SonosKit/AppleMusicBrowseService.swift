import Foundation
import OrderedCollections
import MusicKit
import MusicSearchKit

@MainActor
@Observable
public final class AppleMusicBrowseService {
    public static var shared = AppleMusicBrowseService()
    public var appleMusicAuthorizationStatus: AppleMusicAuthorization = .denied

    @ObservationIgnored private let appleMusicSearchAPI = AppleMusicSearchAPI()
    @ObservationIgnored private let apple = AppleMusicAPI()

    public var userArtists: OrderedSet<PlayableContent> = []
    public var userAlbums: OrderedSet<PlayableContent> = []
    public var userPlaylists: OrderedSet<PlayableContent> = []
    public var usersRecents: OrderedSet<PlayableContent> = []
    public var usersRecentsAdded: OrderedSet<PlayableContent> = []

    var offsets: [String: Int] = [:]

    public init() { }

    public func updateUsersAppleArtists(offset: Int = 0) async {
        guard let playlists = try? await apple.getUserArtists(offset: offset) else { return }
        let newUserArtists = playlists.compactMap(\.toPlayable)
        for newUserArtist in newUserArtists {
            userArtists.updateOrAppend(newUserArtist)
        }
    }

    public func updateUsersAppleAlbums() async {
        guard let container = try? await apple.getUserAlbums(offset: offsets["updateUsersAppleAlbums", default: 0]) else { return }
        let offset = Int(container.next?.components(separatedBy: "=").last ?? "0") ?? 0
        offsets["updateUsersAppleAlbums"] = offset
        let newUserAlbums = container.data.compactMap(\.toPlayable)
        for newUserAlbum in newUserAlbums {
            userAlbums.updateOrAppend(newUserAlbum)
        }
    }

    public func updateUsersApplePlaylists() async {
        guard let container = try? await apple.getUserPlaylists(offset: offsets["updateUsersApplePlaylists", default: 0]) else { return }
        let offset = Int(container.next?.components(separatedBy: "=").last ?? "0") ?? 0
        offsets["updateUsersApplePlaylists"] = offset
        let newUserPlaylists = container.data.compactMap(\.toPlayable)
        for newUserPlaylist in newUserPlaylists {
            userPlaylists.updateOrAppend(newUserPlaylist)
        }
    }

    public func updateUsersRecentPlayed(offset: Int = 0) async {
        guard let container = try? await apple.lookupUsersRecentPlayed(offset: offset) else { return }
        let newUsersRecents = container.data.compactMap(\.toPlayable)
        for newUsersRecent in newUsersRecents {
            usersRecents.updateOrAppend(newUsersRecent)
        }
    }

    public func updateUsersRecentAddedTracks(offset: Int = 0) async {
        guard let container = try? await apple.lookupUsersRecentAddedTracks(offset: offset) else { return }
        let newUsersRecentsTracks = container.data.compactMap(\.toPlayable)
        for newUsersRecentsTrack in newUsersRecentsTracks {
            usersRecentsAdded.updateOrAppend(newUsersRecentsTrack)
        }
    }
    
    public func updateUsersNew(offset: Int = 0) async {
        guard let container = try? await apple.lookupUsersRecentAddedTracks(offset: offset) else { return }
        let newUsersRecentsTracks = container.data.compactMap(\.toPlayable)
        for newUsersRecentsTrack in newUsersRecentsTracks {
            usersRecentsAdded.updateOrAppend(newUsersRecentsTrack)
        }
    }

    public func tracksForUserPlaylists(id: String, offset: Int) async -> ([PlayableContent], total: Int) {
        guard let container = try? await apple.lookupUsersLibraryPlaylist(id: id, offset: offset) else {
            return ([], 0)
        }
//        print(container.meta)
        return (container.data.compactMap(\.toPlayable), container.meta?.total ?? 0)
    }

    public func albumLookup(id: String) async -> [PlayableContent] {
        guard let container = try? await apple.lookupUsersLibraryAlbum(id: id) else { return [] }
        return container.data.compactMap(\.toPlayable)
    }
}
