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

    /// The order of `userPlaylists`, so the Playlists screen and the first
    /// few on the library's front page agree. Remembered across launches.
    public var playlistSort: PlexPlaylistSort {
        didSet { UserDefaults.standard.set(playlistSort.rawValue, forKey: Self.playlistSortKey) }
    }

    /// Whether `playlistSort` runs against its natural direction.
    public var playlistsReversed: Bool {
        didSet { UserDefaults.standard.set(playlistsReversed, forKey: Self.playlistsReversedKey) }
    }

    private static let playlistSortKey = "plex.playlists.sort"
    private static let playlistsReversedKey = "plex.playlists.reversed"

    public init() {
        playlistSort = UserDefaults.standard.string(forKey: Self.playlistSortKey).flatMap { PlexPlaylistSort(rawValue: $0) } ?? .title
        playlistsReversed = UserDefaults.standard.bool(forKey: Self.playlistsReversedKey)
    }

    /// Fetches the playlists in the chosen order. Plex lists them all in one
    /// response, so there is no page to ask for and `offset` is ignored.
    public func updateUserPlaylists(offset: Int? = 0) async {
        let sort = playlistSort, reversed = playlistsReversed
        let playlists = await plexAPI.playlists(sort: sort, reversed: reversed).map(\.toPlayable)
        // A failed fetch leaves the list as it was, and a fetch for an order
        // that has since changed is the next one's to replace.
        guard !playlists.isEmpty, sort == playlistSort, reversed == playlistsReversed else { return }
        // A playlist already here that the server left out is kept, ahead of
        // the rest: Plex can briefly omit a brand-new empty playlist, and the
        // new-playlist flow puts it first. Matched by id, so a renamed one
        // isn't listed twice. Deletions are reflected explicitly by the
        // delete flow, not by dropping here.
        let listed = Set(playlists.map(\.id))
        var ordered = OrderedSet(userPlaylists.filter { !listed.contains($0.id) })
        ordered.append(contentsOf: playlists)
        userPlaylists = ordered
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

