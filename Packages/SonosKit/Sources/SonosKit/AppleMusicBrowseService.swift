import Foundation
import OrderedCollections
import MusicKit
import MusicSearchKit

@MainActor
@Observable
public final class AppleMusicBrowseService {
    public static var shared: AppleMusicBrowseService = {
        let service = AppleMusicBrowseService()
        service.restoreStations()
        return service
    }()
    public var appleMusicAuthorizationStatus: AppleMusicAuthorization = .denied

    @ObservationIgnored private let appleMusicSearchAPI = AppleMusicSearchAPI()
    @ObservationIgnored private let apple = AppleMusicAPI()

    public var userPlaylists: OrderedSet<PlayableContent> = []
    public var userPlaylistFolders: OrderedSet<PlayableContent> = []
    public var usersRecents: OrderedSet<PlayableContent> = []
    public var usersRecentsAdded: OrderedSet<PlayableContent> = []
    public var userRadioStations: OrderedSet<PlayableContent> = []
    public var userStations: OrderedSet<PlayableContent> = []
    public var recommendedAlbums: OrderedSet<PlayableContent> = []

    var offsets: [String: Int] = [:]

    public init() { }

    // MARK: - Library lists

    /// A page of the user's library albums in the requested order.
    ///
    /// MusicKit supplies the order; the rows themselves are looked up on
    /// the web API by id, because MusicKit's library artwork is a
    /// `musickit://` URL nothing but its own views can draw. MusicKit's ids
    /// are the device's own, though, which the web API mostly doesn't know,
    /// so most rows are MusicKit's (`toPlayableLibraryAlbum`, its cover's
    /// https address worked out from the artwork's path). Either way a
    /// favorite is marked from the favorites list (`markingFavorites`)
    /// when `marksFavorites`: the lists the star shows in, not the widget's
    /// or CarPlay's reads.
    public func libraryAlbums(offset: Int = 0, sort: AppleLibrarySort = .title, descending: Bool = false, marksFavorites: Bool = false) async -> [PlayableContent] {
        async let keys = marksFavorites ? favoriteKeys(for: .albums) : nil
        guard let albums = try? await apple.libraryAlbums(sort: sort, descending: descending, offset: offset) else { return [] }
        let rows = (try? await apple.libraryAlbums(ids: albums.map(\.id.rawValue))) ?? []
        let rowsByID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let page = albums.map { album in
            rowsByID[album.id.rawValue]?.toPlayable ?? album.toPlayableLibraryAlbum
        }
        return Self.markingFavorites(page, keys: await keys)
    }

    /// A page of the user's library songs in the requested order, from
    /// MusicKit's index of the library. MusicKit's own rows, with the ids
    /// `ApplicationMusicPlayer` plays (a downloaded copy offline too).
    /// MusicKit can't sort songs by release date, so that order is worked
    /// out once over the whole library (`songIDsByReleaseDate`) and paged
    /// from.
    public func librarySongs(offset: Int = 0, sort: AppleLibrarySort = .title, descending: Bool = false) async -> [PlayableContent] {
        async let keys = favoriteKeys(for: .songs)
        let songs: [Song]
        if sort == .releaseDate {
            guard let ids = await songIDsByReleaseDate(descending: descending), offset < ids.count else { return [] }
            songs = await apple.librarySongs(ids: Array(ids[offset..<min(offset + libraryPageSize, ids.count)]))
        } else {
            guard let page = try? await apple.librarySongs(sort: sort, descending: descending, offset: offset, limit: libraryPageSize) else { return [] }
            songs = page
        }
        return Self.markingFavorites(songs.map(\.toPlayableLibraryTrack), keys: await keys)
    }

    /// A page of the user's library artists from the web API, in Apple's
    /// order (A to Z), each saying whether it's a favorite. Not MusicKit's:
    /// an artist opens by its web id (`r.…`), which MusicKit's rows don't
    /// carry. Z to A reads them all first and turns them round, as one
    /// page; the reading is kept five minutes, so flipping back and forth
    /// doesn't read them all again.
    public func libraryArtists(offset: Int = 0, descending: Bool = false) async -> [PlayableContent] {
        guard descending else {
            guard let page = await apple.getLibrary(.artists, offset: offset, limit: libraryPageSize) else { return [] }
            return page.data.compactMap(\.toPlayable)
        }
        guard offset == 0 else { return [] }
        if let allArtists, allArtists.readAt.timeIntervalSinceNow > -300 {
            return allArtists.artists.reversed()
        }
        var artists: [PlayableContent] = []
        var next: Int? = 0
        while let pageOffset = next, !Task.isCancelled {
            // A failed page ends it with what came before, kept for nothing.
            guard let page = await apple.getLibrary(.artists, offset: pageOffset, limit: libraryPageSize) else {
                return artists.reversed()
            }
            artists += page.data.compactMap(\.toPlayable)
            next = page.nextOffset
        }
        if next == nil {
            allArtists = (artists, Date())
        }
        return artists.reversed()
    }

    @ObservationIgnored private var allArtists: (artists: [PlayableContent], readAt: Date)?

    /// Apple's largest page.
    private let libraryPageSize = 100

    /// Every library song's MusicKit id by release date, oldest first, a
    /// song with none at the end; titles keep MusicKit's title order. Kept
    /// five minutes, from one read of the library (`librarySongReleaseDates`).
    private func songIDsByReleaseDate(descending: Bool) async -> [String]? {
        let sorted: [(id: String, released: Date?)]
        if let songsByRelease, songsByRelease.readAt.timeIntervalSinceNow > -300 {
            sorted = songsByRelease.songs
        } else {
            guard let dates = await apple.librarySongReleaseDates() else { return nil }
            sorted = dates.enumerated().sorted { a, b in
                switch (a.element.released, b.element.released) {
                case (nil, nil): a.offset < b.offset
                case (nil, _): false
                case (_, nil): true
                case let (x?, y?): x == y ? a.offset < b.offset : x < y
                }
            }
            .map(\.element)
            songsByRelease = (sorted, Date())
        }
        // Newest first keeps the songs with no date at the end.
        guard descending else { return sorted.map(\.id) }
        let dated = sorted.filter { $0.released != nil }
        return (dated.reversed() + sorted.filter { $0.released == nil }).map(\.id)
    }

    @ObservationIgnored private var songsByRelease: (songs: [(id: String, released: Date?)], readAt: Date)?

    // MARK: - Favorites

    /// When each item read from the web API was released and added to the
    /// library, as Apple writes them (`2022-02-11`, `2022-08-06T02:18:57Z`),
    /// by id: what the favorites are sorted on. Kept here rather than on
    /// the row, which has no field for them.
    public struct LibraryDates: Sendable {
        public let released: String?
        public let added: String?
    }

    @ObservationIgnored private var libraryDates: [String: LibraryDates] = [:]

    public func dates(of id: String) -> LibraryDates? {
        libraryDates[id]
    }

    /// Each kind's favorites, as last read in full.
    @ObservationIgnored private var favoriteItems: [AppleLibraryResource: [PlayableContent]] = [:]
    /// The read each kind has on its way. A second ask waits for it rather
    /// than sending another, so a list opening while the library page's
    /// read is out doesn't take an empty list for "no favorites".
    @ObservationIgnored private var favoritesInFlight: [AppleLibraryResource: Task<[PlayableContent]?, Never>] = [:]

    /// Every favorite of a kind, read whole from the web API: favorites are
    /// few, a page or two, and every order Cue gives them is made from all
    /// of them. The read runs in a task of its own, so a screen leaving
    /// mid-read can't cancel it into an empty list, and a failed read
    /// changes nothing: the last good one is given back.
    public func favorites(_ resource: AppleLibraryResource) async -> [PlayableContent] {
        if let running = favoritesInFlight[resource] {
            return await running.value ?? favoriteItems[resource] ?? []
        }
        let task = Task { await self.readFavorites(resource) }
        favoritesInFlight[resource] = task
        let read = await task.value
        favoritesInFlight[resource] = nil
        guard let read else { return favoriteItems[resource] ?? [] }
        favoriteItems[resource] = read
        return read
    }

    /// The library page's Favorites: the favorite playlists (Favorite Songs
    /// among them), albums and artists, in that order.
    public func favoritesShelf() async -> [PlayableContent] {
        async let playlists = favorites(.playlists)
        async let albums = favorites(.albums)
        async let artists = favorites(.artists)
        return await playlists + albums + artists
    }

    private func readFavorites(_ resource: AppleLibraryResource) async -> [PlayableContent]? {
        // Songs from Favorite Songs, decided at the first page and kept for
        // the rest, so the pages all come from one list.
        let playlistID = resource == .songs ? await favoriteSongsPlaylistID() : nil
        var items: [AppleLibraryItem] = []
        var next: Int? = 0
        while let offset = next {
            let page: AppleLibraryContainer?
            if let playlistID {
                page = await apple.getLibraryPlaylistTracks(id: playlistID, offset: offset, limit: libraryPageSize)
            } else {
                page = await apple.getLibrary(resource, offset: offset, limit: libraryPageSize, favoritesOnly: true)
            }
            guard let page else { return nil }
            items += page.data
            next = page.nextOffset
        }
        for item in items {
            libraryDates[item.id] = LibraryDates(released: item.attributes.releaseDate, added: item.attributes.dateAdded)
        }
        // Whatever the read says, they're favorites: a Favorite Songs track
        // read through the playlist may not say.
        return items.compactMap(\.toPlayable).map { item in
            var item = item
            item.metadata?.userRating = 1
            return item
        }
    }

    /// Favorite Songs, once found.
    @ObservationIgnored private var foundFavoriteSongsPlaylistID: String?

    /// The Favorite Songs playlist: every song favorited, in the library or
    /// not. The library's favorites filter only has songs that were added to
    /// the library; on 2026-11-10 it had 21 of a Favorite Songs of 64, the
    /// other 43 favorited without being added. So the favorite songs are
    /// read from the playlist when it can be told apart: a favorite
    /// playlist that can't be edited, with a person's playlist id (`pl.u-`).
    /// A curator's playlist added from the catalog can't be edited either,
    /// but its id is `pl.` and a hash. The English name only breaks a tie,
    /// as it's localized. Not found (no favorites yet, or a failed read) is
    /// asked again next time.
    private func favoriteSongsPlaylistID() async -> String? {
        if let found = foundFavoriteSongsPlaylistID {
            return found
        }
        guard let container = await apple.getLibrary(.playlists, favoritesOnly: true) else { return nil }
        let candidates = container.data.filter {
            $0.attributes.canEdit == false && $0.attributes.playParams?.globalId?.hasPrefix("pl.u-") == true
        }
        let found = (candidates.first { $0.attributes.name == "Favorite Songs" } ?? candidates.first)?.id
        foundFavoriteSongsPlaylistID = found
        return found
    }

    // MARK: - Favorites on MusicKit's rows

    /// The favorites of a kind as match keys (`favoriteKey`), or nil when
    /// they've never been read: a row is then left saying nothing, rather
    /// than "not a favorite". Read once a screen; the library page's
    /// Favorites or a favorite set from a menu reads them again.
    private func favoriteKeys(for resource: AppleLibraryResource) async -> Set<String>? {
        if favoriteItems[resource] == nil {
            _ = await favorites(resource)
        }
        return favoriteItems[resource].map { Set($0.map(Self.favoriteKey)) }
    }

    /// MusicKit's ids are the device's own and the web API's favorites
    /// carry the web's, so a MusicKit row is matched to a favorite by name:
    /// its title and artist, folded for case and accents. Favorites are few,
    /// and an album's or a song's title and artist are the library's own on
    /// both sides.
    private static func favoriteKey(_ item: PlayableContent) -> String {
        [item.title, item.metadata?.artist ?? ""]
            .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil) }
            .joined(separator: "\u{1F}")
    }

    private static func markingFavorites(_ rows: [PlayableContent], keys: Set<String>?) -> [PlayableContent] {
        guard let keys else { return rows }
        return rows.map { row in
            let isFavorite = keys.contains(favoriteKey(row))
            var row = row
            row.metadata?.userRating = isFavorite ? 1 : 0
            return row
        }
    }

    /// The web API's id for a library row from MusicKit, whose own id the
    /// web API doesn't know: to favorite it or take it off. A favorite's
    /// is in the favorites read; any other is searched for in the library
    /// by title and matched by artist. Nil for a row that isn't MusicKit's
    /// (its id is the web's already) or that can't be found.
    public func webLibraryID(for item: PlayableContent) async -> String? {
        guard item.content.type == .libraryAlbum || item.content.type == .libraryTrack,
              item.content.id.allSatisfy(\.isNumber) else { return nil }
        let resource: AppleLibraryResource = item.content.type == .libraryAlbum ? .albums : .songs
        let key = Self.favoriteKey(item)
        if let favorite = favoriteItems[resource]?.first(where: { Self.favoriteKey($0) == key }),
           !favorite.content.id.allSatisfy(\.isNumber) {
            return favorite.content.id
        }
        let type = resource == .albums ? "library-albums" : "library-songs"
        guard let results = try? await apple.librarySearch(term: item.title, types: type) else { return nil }
        let candidates = resource == .albums
            ? (results.results.libraryAlbums?.data ?? []).compactMap(\.toPlayable)
            : (results.results.librarySongs?.data ?? []).compactMap(\.toPlayable)
        return candidates.first { Self.favoriteKey($0) == key }?.content.id
    }

    /// A favorite set or taken off from a menu: the favorites are read again
    /// next time, so MusicKit's rows are marked from what's true now.
    public func favoritesChanged() {
        favoriteItems = [:]
    }

    public func updateUsersApplePlaylists(offset: Int, limit: Int? = nil) async {
        guard let container = try? await apple.getUserPlaylists(offset: offset, limit: limit) else { return }
        let offset = Int(container.next?.components(separatedBy: "=").last ?? "0") ?? 0
        offsets["updateUsersApplePlaylists"] = offset
        let newUserPlaylists = container.data.compactMap(\.toPlayable)
        // One write, and only for a change: each `updateOrAppend` on the
        // observed set counted as a write, so every open of Search updated
        // the Apple Playlists row for nothing.
        var updated = userPlaylists
        for newUserPlaylist in newUserPlaylists {
            updated.updateOrAppend(newUserPlaylist)
        }
        guard !updated.displaysSame(as: userPlaylists) else { return }
        userPlaylists = updated
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
    
    /// The user's personal stations, then the ones played lately. A first
    /// page read whole replaces the list, so a station no longer played
    /// lately goes rather than staying on from the list kept at the last
    /// launch (`restoreStations`); later pages add to it.
    public func updateRadioStations(offset: Int = 0, limit: Int? = nil) async {
        guard let personal = try? await apple.lookupAppleRadioStations(offset: offset) else { return }
        let recent = try? await apple.lookupUsersRecentRadioStations(offset: offset)
        let read = (personal.data + (recent?.data ?? [])).compactMap(\.toPlayable)
        if offset == 0, recent != nil {
            // Asked each time the Radio tab shows: the same stations again
            // aren't written, which would redraw every row of the tab.
            let fresh = OrderedSet(read)
            guard fresh != userStations else { return }
            userStations = fresh
            keepStations()
        } else {
            for station in read {
                userStations.updateOrAppend(station)
            }
        }
    }

    /// Apple's own live stations — Apple Music 1 and the rest of the
    /// broadcast lineup, as opposed to the user's personal ones.
    public var liveStations: OrderedSet<PlayableContent> = []

    public func updateLiveRadioStations() async {
        guard let container = try? await apple.lookupAppleLiveRadioStations() else { return }
        // Replaced whole: one Apple drops from the lineup goes. Only when
        // it changed, as with the personal ones.
        let fresh = OrderedSet(container.data.compactMap(\.toPlayable))
        guard fresh != liveStations else { return }
        liveStations = fresh
        keepStations()
    }

    // MARK: - Kept stations

    /// The stations as last read (`ShelfCache`), so the Radio tab and the
    /// library's Personal Stations draw them at once while Apple is read
    /// behind them. A station is its id, name and artwork, so a kept one
    /// plays as a fresh one does.
    private struct KeptStations: Codable, Sendable {
        var live: [PlayableContent]
        var personal: [PlayableContent]
    }

    private static let keptStationsName = "AppleRadio"

    /// Only for `shared`: a service made for one screen reads its own.
    private func restoreStations() {
        guard let kept = ShelfCache.load(KeptStations.self, named: Self.keptStationsName) else { return }
        liveStations = OrderedSet(kept.live)
        userStations = OrderedSet(kept.personal)
    }

    private func keepStations() {
        ShelfCache.save(KeptStations(live: Array(liveStations), personal: Array(userStations)), named: Self.keptStationsName)
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
