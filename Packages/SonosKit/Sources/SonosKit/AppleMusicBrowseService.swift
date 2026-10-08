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
    public var userSongs: OrderedSet<PlayableContent> = []
    public var userPlaylists: OrderedSet<PlayableContent> = []
    public var userPlaylistFolders: OrderedSet<PlayableContent> = []
    public var usersRecents: OrderedSet<PlayableContent> = []
    public var usersRecentsAdded: OrderedSet<PlayableContent> = []
    public var userRadioStations: OrderedSet<PlayableContent> = []
    public var userStations: OrderedSet<PlayableContent> = []
    public var recommendedAlbums: OrderedSet<PlayableContent> = []

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
    
    /// A page of the user's library albums in the requested order. Unlike
    /// `updateUsersAppleAlbums` this returns the rows rather than merging
    /// them into `userAlbums`: a sorted list pages by offset and owns its
    /// own rows, so a change of order replaces them.
    ///
    /// MusicKit supplies the order; the rows themselves come from the web
    /// API, looked up by id, because MusicKit's library artwork is a
    /// `musickit://` URL nothing but its own views can draw. An album the
    /// web API doesn't return falls back to the MusicKit row, which at
    /// least has its name.
    public func libraryAlbums(offset: Int = 0, sort: AppleLibraryAlbumSort = .title, descending: Bool = false) async -> [PlayableContent] {
        guard let albums = try? await apple.libraryAlbums(sort: sort, descending: descending, offset: offset) else { return [] }
        let rows = (try? await apple.libraryAlbums(ids: albums.map(\.id.rawValue))) ?? []
        let rowsByID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return albums.map { album in
            rowsByID[album.id.rawValue]?.toPlayable ?? album.toPlayableLibraryAlbum
        }
    }

    public func updateUsersAppleSongs() async {
        // Past the last page. Reading its missing `next` as offset 0 started
        // the library over from the first page whenever the end was scrolled
        // to, and again on the next scroll, for good.
        guard !userSongsComplete else { return }
        guard let container = try? await apple.getUserSongs(offset: offsets["updateUsersAppleSongs", default: 0]) else { return }
        if let next = container.next {
            offsets["updateUsersAppleSongs"] = Int(next.components(separatedBy: "=").last ?? "") ?? 0
        } else {
            userSongsComplete = true
        }
        var songs = userSongs
        for song in container.data.compactMap(\.toPlayable) {
            songs.updateOrAppend(song)
        }
        // One update for the page, not one per song.
        userSongs = songs
    }

    /// The whole song library has been read (see `updateUsersAppleSongs`).
    @ObservationIgnored private var userSongsComplete = false

    public func updateUsersApplePlaylists(offset: Int, limit: Int? = nil) async {
        guard let container = try? await apple.getUserPlaylists(offset: offset, limit: limit) else { return }
        let offset = Int(container.next?.components(separatedBy: "=").last ?? "0") ?? 0
        offsets["updateUsersApplePlaylists"] = offset
        let newUserPlaylists = container.data.compactMap(\.toPlayable)
        for newUserPlaylist in newUserPlaylists {
            userPlaylists.updateOrAppend(newUserPlaylist)
        }
    }
    
    public func updateUsersApplePlaylistFolders(offset: Int = 0) async {
        guard let container = try? await apple.getUserPlaylistsFolders(offset: offset) else { return }
        let newUserPlaylistFolders = container.data.compactMap(\.toPlayable)
        for newUserPlaylistFolder in newUserPlaylistFolders {
            userPlaylistFolders.updateOrAppend(newUserPlaylistFolder)
        }
    }
    
    public func getPlaylistFolderContents(id: String, offset: Int) async -> ([PlayableContent], total: Int) {
        guard let container = try? await apple.getPlaylistFolder(id: id, offset: offset) else {
            return ([], 0)
        }
        return (container.data.compactMap(\.toPlayable), container.meta?.total ?? 0)
    }

    public func updateUsersRecentPlayed(offset: Int = 0, limit: Int? = nil) async {
        guard let container = try? await apple.lookupUsersRecentPlayed(offset: offset) else { return }
        let newUsersRecents = container.data.compactMap(\.toPlayable)
        // The first page is the newest: it goes in front, so something just
        // played moves to the top. Merged in place, an album already in the
        // list kept its old position and anything new went to the end, so
        // the row never looked like it changed.
        guard offset > 0 else {
            var fresh = OrderedSet(newUsersRecents)
            fresh.append(contentsOf: usersRecents)
            usersRecents = fresh
            return
        }
        for newUsersRecent in newUsersRecents {
            usersRecents.updateOrAppend(newUsersRecent)
        }
    }

    public func updateUsersRecentAddedTracks(offset: Int = 0, limit: Int? = nil) async {
        guard let container = try? await apple.lookupUsersRecentAddedTracks(offset: offset, limit: limit) else { return }
        let newUsersRecentsTracks = container.data.compactMap(\.toPlayable)
        // Newest first, for the same reason as Recently Played.
        guard offset > 0 else {
            var fresh = OrderedSet(newUsersRecentsTracks)
            fresh.append(contentsOf: usersRecentsAdded)
            usersRecentsAdded = fresh
            return
        }
        for newUsersRecentsTrack in newUsersRecentsTracks {
            usersRecentsAdded.updateOrAppend(newUsersRecentsTrack)
        }
    }
    
    public func updateUsersRadioStations(offset: Int = 0, limit: Int? = nil) async {
        guard let container = try? await apple.lookupUsersRecentRadioStations(offset: offset, limit: limit) else { return }
        let newUsersRecentsTracks = container.data.compactMap(\.toPlayable)
        for newUsersRecentsTrack in newUsersRecentsTracks {
            userRadioStations.updateOrAppend(newUsersRecentsTrack)
        }
    }
    
    public func updateRadioStations(offset: Int = 0, limit: Int? = nil) async {
        guard let container = try? await apple.lookupAppleRadioStations(offset: offset) else { return }
        let newUsersRecentsTracks = container.data.compactMap(\.toPlayable)
        for newUsersRecentsTracks in newUsersRecentsTracks {
            userStations.updateOrAppend(newUsersRecentsTracks)
        }
        
        guard let container = try? await apple.lookupUsersRecentRadioStations(offset: offset) else { return }
        let newUsersRecentRadioStations = container.data.compactMap(\.toPlayable)
        for newUsersRecentRadioStation in newUsersRecentRadioStations {
            userStations.updateOrAppend(newUsersRecentRadioStation)
        }
    }

    /// Apple's own live stations — Apple Music 1 and the rest of the
    /// broadcast lineup, as opposed to the user's personal ones.
    public var liveStations: OrderedSet<PlayableContent> = []

    public func updateLiveRadioStations() async {
        guard let container = try? await apple.lookupAppleLiveRadioStations() else { return }
        for station in container.data.compactMap(\.toPlayable) {
            liveStations.updateOrAppend(station)
        }
    }

    /// Everything the Radio tab lists for Apple Music: the live stations
    /// first, then the user's personal and recently played ones.
    public var radioStations: [PlayableContent] {
        Array(liveStations) + userStations.filter { !liveStations.contains($0) }
    }

    public func tracksForUserPlaylists(id: String, offset: Int) async -> ([PlayableContent], total: Int) {
        guard let container = try? await apple.lookupUsersLibraryPlaylist(id: id, offset: offset) else {
            return ([], 0)
        }
//        print(container.meta)
        return (container.data.compactMap(\.toPlayable), container.meta?.total ?? 0)
    }

    public func albumLookup(id: String) async -> [PlayableContent] {
        if let container = try? await apple.lookupUsersLibraryAlbum(id: id) {
            let tracks = container.data.compactMap(\.toPlayable)
            if !tracks.isEmpty { return tracks }
        }
        // The Albums list pages through MusicKit, whose library ids are the
        // device's own (a long number) rather than the web API's `l.…`, so
        // the web API knows none of them and the album opened empty. Ask
        // MusicKit for the album it named.
        var request = MusicLibraryRequest<Album>()
        request.filter(matching: \.id, equalTo: MusicItemID(id))
        guard let album = try? await request.response().items.first,
              let detailed = try? await album.with([.tracks]),
              let tracks = detailed.tracks else { return [] }
        return tracks.compactMap { track in
            guard case let .song(song) = track else { return nil }
            return song.toPlayableLibraryTrack
        }
    }

    public func updateRecommendedAlbums(offset: Int = 0, limit: Int = 25) async {
        guard let container = try? await apple.getUserRecommendations(offset: offset, limit: limit) else { return }
        let newRecommendedAlbums = container.data.compactMap(\.toPlayable)
        for newRecommendedAlbum in newRecommendedAlbums {
            recommendedAlbums.updateOrAppend(newRecommendedAlbum)
        }
    }
}
