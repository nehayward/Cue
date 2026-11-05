#if os(iOS) && !targetEnvironment(macCatalyst)
import Defaults
import MusicKit
import MusicSearchKit
import SonosKit

/// An artist's page in the car: their top songs and their albums, read
/// from the services the phone's artist page reads (`ArtistDetailView`),
/// for the providers whose music plays on this device.
///
/// It opens from a song (Now Playing's artist, `CarPlayInterface`) as well
/// as from an artist (a search result, a recent search), so the artist is
/// looked up the way the phone's page finds a song's: Apple Music's by the
/// song's catalog artist, else by name; Plex's and Subsonic's by the
/// song's artist id; the Files folder's from its index. Offline, or when
/// the service has nothing, it's the artist's songs on this iPhone.
@MainActor
enum CarPlayArtist {
    struct Page: Sendable {
        /// The artist, for their picture, when the service gave one.
        let artist: PlayableContent?
        let name: String
        /// The heading over `songs`: what the service ranks them by.
        let songsTitle: String
        let songs: [PlayableContent]
        /// Each album once, newest first.
        let albums: [PlayableContent]

        var isEmpty: Bool { songs.isEmpty && albums.isEmpty }
    }

    /// How many songs the page lists: the top of the service's list.
    private static let songLimit = 10

    /// How long the service has to answer before the page settles for
    /// what's on this iPhone: a home Plex or Subsonic server out of reach
    /// (away from home) would hold the car on a spinner for a minute.
    private static let serviceTimeout: Duration = .seconds(10)

    /// Whether `content` has an artist page in the car: an artist, or a
    /// song naming one, from a provider the page can read, or with songs
    /// on this iPhone.
    static func canOpen(for content: PlayableContent) -> Bool {
        let type = content.content.type
        if OnDeviceLibrary.isContainer(content) {
            return type == .artist
        }
        if type.isArtist {
            return readsArtists(of: content.content.service)
        }
        guard type.isTrack, !(content.metadata?.artist ?? "").isEmpty else { return false }
        return readsArtists(of: content.content.service) || OnDeviceLibrary.artist(of: content) != nil
    }

    /// The providers whose artists the page reads.
    private static func readsArtists(of service: MusicService) -> Bool {
        switch service {
        case .apple: MusicAuthorization.currentStatus == .authorized
        case .plex, .subsonic, .files: true
        default: false
        }
    }

    /// `content`'s artist page: the artist itself, or a song's artist. Nil
    /// when nothing about them could be read.
    static func page(for content: PlayableContent) async -> Page? {
        let timeout = serviceTimeout
        let page = await withTaskGroup(of: Page?.self) { group -> Page? in
            group.addTask { await serviceArtist(for: content) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        let player = LocalPlaybackService.shared
        if let page, !page.isEmpty {
            return Page(
                artist: page.artist,
                name: page.name,
                songsTitle: page.songsTitle,
                songs: page.songs.filter { player.canPlayLocally($0) },
                albums: page.albums.filter { player.canPlayAnywhereLocally($0) }
            )
        }
        return onDevice(for: content) ?? page
    }

    /// The artist from their service, as the phone's page reads them. Not
    /// while offline: no service can answer, and the car would sit on a
    /// spinner until each gave up.
    private static func serviceArtist(for content: PlayableContent) async -> Page? {
        guard !OfflineMode.shared.isActive, !OnDeviceLibrary.isContainer(content) else { return nil }
        let isArtist = content.content.type.isArtist
        switch content.content.service {
        case .apple:
            guard MusicAuthorization.currentStatus == .authorized,
                  let id = await appleArtistID(for: content) else { return nil }
            return await appleArtist(id: id)
        case .plex:
            guard let id = isArtist ? content.content.id : await plexArtistID(of: content) else { return nil }
            return await plexArtist(id: id, named: content.metadata?.artist ?? content.title)
        case .subsonic:
            guard let id = isArtist ? content.content.id : await subsonicArtistID(of: content) else { return nil }
            return await subsonicArtist(id: id)
        case .files:
            let files = FilesLibraryService.shared
            await files.scanIfNeeded()
            let id = isArtist ? content.content.id : (content.metadata?.artistID ?? files.track(id: content.content.id)?.metadata?.artistID)
            guard let id, let artist = files.artist(id: id) else { return nil }
            return Page(
                artist: artist,
                name: artist.title,
                // Files carry no play counts: every song, in the folder's
                // order.
                songsTitle: "Songs",
                songs: Array(files.artistTracks(artistID: id).prefix(songLimit)),
                albums: files.artistAlbums(artistID: id)
            )
        default:
            return nil
        }
    }

    /// The artist's songs and albums on this iPhone.
    private static func onDevice(for content: PlayableContent) -> Page? {
        let container: PlayableContent
        if OnDeviceLibrary.isContainer(content) {
            container = content
        } else if content.content.type.isTrack, let group = OnDeviceLibrary.artist(of: content) {
            container = group.container
        } else {
            return nil
        }
        let songs = OnDeviceLibrary.tracks(inContainer: container) ?? []
        let albums = OnDeviceLibrary.albums(ofArtist: container).map(\.container)
        guard !songs.isEmpty || !albums.isEmpty else { return nil }
        return Page(artist: container, name: container.title, songsTitle: "Songs on This iPhone", songs: songs, albums: albums)
    }

    // MARK: - Apple Music

    /// The catalog artist: an artist's own id, a catalog song's first
    /// artist, else the artist of that name (a library song or artist,
    /// whose ids are the library's).
    private static func appleArtistID(for content: PlayableContent) async -> String? {
        switch content.content.type {
        case .artist:
            return content.content.id
        case .track:
            let song: Song? = try? await MusicSearchService.shared.lookup(id: content.content.id)
            if let id = song?.artists?.first?.id.rawValue {
                return id
            }
        default:
            break
        }
        let name = content.content.type.isArtist ? content.title : content.metadata?.artist
        return await appleArtistID(named: name)
    }

    /// An Apple Music artist named exactly `name`, from a catalog search.
    private static func appleArtistID(named name: String?) async -> String? {
        guard let name, !name.isEmpty else { return nil }
        var request = MusicCatalogSearchRequest(term: name, types: [Artist.self])
        request.limit = 5
        guard let results = try? await request.response() else { return nil }
        let wanted = name.lowercased()
        return results.artists.first { $0.name.lowercased() == wanted }?.id.rawValue
    }

    /// Their top songs, and their albums as Apple Music's artist page lists
    /// them (`fullAlbums`), else the catalog's albums but singles.
    private static func appleArtist(id: String) async -> Page? {
        let search = MusicSearchService.shared
        async let kinds = search.artistAlbumKinds(id: id)
        guard let artist: Artist = try? await search.lookup(id: id) else { return nil }
        let songs = (artist.topSongs.map { Array($0) } ?? []).map(\.toPlayable)
        var albums = (await kinds).map { eachAlbumOnce($0.albums) } ?? []
        if albums.isEmpty {
            albums = newestFirst((artist.albums.map { Array($0) } ?? []).map(\.toPlayable).filter { !($0.metadata?.isSingle ?? false) })
        }
        return Page(
            artist: artist.toPlayable,
            name: artist.name,
            songsTitle: "Top Songs",
            songs: Array(songs.prefix(songLimit)),
            albums: albums
        )
    }

    // MARK: - Plex

    private static func plexArtistID(of track: PlayableContent) async -> String? {
        if let id = track.metadata?.artistID, !id.isEmpty {
            return id
        }
        guard let key = track.id.removingPercentEncoding?.components(separatedBy: ":").last else { return nil }
        return await MusicSearchService.shared.lookupPlexSong(with: key)?.metadata?.artistID
    }

    /// Their albums, and their songs played most on the server.
    private static func plexArtist(id: String, named name: String) async -> Page? {
        let search = MusicSearchService.shared
        async let albums = search.lookupPlexArtistAlbums(id: id)
        async let artist = search.lookupPlexArtist(id: id)
        async let songs = search.lookupPlexTracks(id: id)
        let (found, shown, played) = await (albums, artist, songs)
        guard shown != nil || !found.isEmpty else { return nil }
        return Page(
            artist: shown,
            name: shown?.title ?? name,
            songsTitle: "Most Played",
            songs: Array(played.prefix(songLimit)),
            albums: eachAlbumOnce(found)
        )
    }

    // MARK: - Subsonic

    private static func subsonicArtistID(of track: PlayableContent) async -> String? {
        if let id = track.metadata?.artistID, !id.isEmpty {
            return id
        }
        return await MusicSearchService.shared.lookupSubsonicTrack(with: track.content.id)?.metadata?.artistID
    }

    /// Their albums from one `getArtist`, and their most-played songs,
    /// which a server without play data has none of.
    private static func subsonicArtist(id: String) async -> Page? {
        let search = MusicSearchService.shared
        guard let found = await search.lookupSubsonicArtistWithAlbums(id: id) else { return nil }
        let songs = await search.subsonicArtistTopSongs(artistName: found.artist.title)
        return Page(
            artist: found.artist,
            name: found.artist.title,
            songsTitle: "Top Songs",
            songs: Array(songs.prefix(songLimit)),
            albums: newestFirst(found.albums)
        )
    }

    // MARK: - Albums

    /// Each album once by its plain title, newest first: the phone's
    /// artist page's Albums (`AlbumEditions`).
    private static func eachAlbumOnce(_ albums: [PlayableContent]) -> [PlayableContent] {
        AlbumEditions.albums(albums, title: \.title, released: { $0.metadata?.albumYear })
            .map { album in
                let item = album.item
                return PlayableContent(title: album.title, subtitle: item.subtitle, thumbnail: item.thumbnail, artwork: item.artwork, content: item.content, previewURL: item.previewURL, metadata: item.metadata)
            }
    }

    private static func newestFirst(_ albums: [PlayableContent]) -> [PlayableContent] {
        albums.sorted { ($0.metadata?.albumYear ?? .distantPast) > ($1.metadata?.albumYear ?? .distantPast) }
    }
}
#endif
