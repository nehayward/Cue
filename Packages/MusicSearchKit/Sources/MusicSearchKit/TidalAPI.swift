import Foundation

public final class TidalAPI {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    public func search(for query: String, limit: Int = 20) async -> TidalResult? {
        if query.count < 1 { return nil }
        
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openapi.tidal.com"
        // Tidal retired the `/searchResults/{query}` form — every query now
        // fails with 400 INVALID_RESOURCE_ID — in favour of a query filter.
        // Includes are capped at 10 resource paths; this set pulls in each
        // track's album art and artists so rows have artwork and a subtitle.
        components.path = "/v2/searchResults"
        components.queryItems = [
            URLQueryItem(name: "filter[query]", value: query),
            URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US"),
            URLQueryItem(name: "include", value: "tracks.albums.coverArt,tracks.artists,artists.profileArt,albums.coverArt,playlists.coverArt")
        ]

        guard let url = components.url else {
            return nil
        }

        do {
            guard let tidalResponse: TidalApiResponse? = try await loadAuthorized(url) else {
                return nil
            }
            return tidalResponse?.toTidalResult
        } catch {

            return nil
        }
    }

    public func track(with id: String) async -> TidalTrackResource? {
        guard let url = Self.url(path: "/v2/tracks/\(id)", include: "artists,albums.coverArt"),
              let document: TidalDocument = try? await loadAuthorized(url) else { return nil }
        let album = document.related(document.data.relationships?.albums).first.flatMap { document.album($0) }
        return document.track(document.data, album: album)
    }

    public func album(with id: String) async -> TidalAlbumResource? {
        guard let url = Self.url(path: "/v2/albums/\(id)", include: "artists,coverArt"),
              let document: TidalDocument = try? await loadAuthorized(url) else { return nil }
        return document.album(document.data)
    }

    /// An album's tracks in running order. `items` is the only relationship
    /// that lists them in order — `included` is id-sorted and also carries the
    /// album's artists, which aren't tracks. It's paged at 20, so longer
    /// albums follow `nextCursor` for the rest.
    public func albumSongs(id: String) async -> [TidalTrackResource] {
        guard let url = Self.url(path: "/v2/albums/\(id)", include: "items,artists,coverArt"),
              let document: TidalDocument = try? await loadAuthorized(url),
              let album = document.album(document.data) else { return [] }

        var items = document.related(document.data.relationships?.items)
        var cursor = document.data.relationships?.items?.links?.meta?.nextCursor
        var pages = 0
        while let next = cursor, pages < Self.maxRelationshipPages {
            guard let pageURL = Self.url(
                path: "/v2/albums/\(id)/relationships/items",
                include: "items",
                extra: [URLQueryItem(name: "page[cursor]", value: next)]
            ),
                  let page: TidalRelationshipPage = try? await loadAuthorized(pageURL) else { break }
            items += page.resources
            cursor = page.links?.meta?.nextCursor
            pages += 1
        }

        return items
            .filter { $0.type == "tracks" }
            .compactMap { document.track($0, album: album, fallbackArtists: album.artists) }
    }

    /// Cap on follow-up pages for one relationship (20 items each), so a
    /// runaway cursor can't loop forever.
    private static let maxRelationshipPages = 10

    /// An artist's top tracks, in Tidal's order, with each track's album (and
    /// so its artwork).
    public func artistSongs(id: String) async -> [TidalTrackResource] {
        guard let url = Self.url(path: "/v2/artists/\(id)", include: "tracks.albums.coverArt,profileArt", extra: [
            URLQueryItem(name: "collapseBy", value: "FINGERPRINT"),
        ]),
              let document: TidalDocument = try? await loadAuthorized(url),
              let artist = document.artist(document.data) else { return [] }
        return document.related(document.data.relationships?.tracks).compactMap { track in
            let album = document.related(track.relationships?.albums).first.flatMap { document.album($0) }
            return document.track(track, album: album, fallbackArtists: [artist])
        }
    }

    // MARK: Previews

    /// Tidal's own 30-second preview of a track: a signed, short-lived HLS
    /// stream (unencrypted HE-AAC, which AVPlayer plays as-is). Without a
    /// user subscription `trackManifests` answers with
    /// `trackPresentation: PREVIEW`, so this needs no sign-in. Resolve it at
    /// play time — the signature expires, so it can't be stored on a row.
    public func previewStreamURL(trackID: String) async -> URL? {
        guard let url = Self.url(path: "/v2/trackManifests/\(trackID)", include: "", extra: [
            URLQueryItem(name: "manifestType", value: "HLS"),
            URLQueryItem(name: "formats", value: "HEAACV1"),
            URLQueryItem(name: "uriScheme", value: "HTTPS"),
            URLQueryItem(name: "usage", value: "PLAYBACK"),
            URLQueryItem(name: "adaptive", value: "false"),
        ]) else { return nil }

        struct Manifest: Codable {
            struct Resource: Codable {
                struct Attributes: Codable { let uri: String? }
                let attributes: Attributes?
            }
            let data: Resource?
        }
        guard let manifest: Manifest = try? await loadAuthorized(url),
              let uri = manifest.data?.attributes?.uri else { return nil }
        return URL(string: uri)
    }

    /// A stable stand-in for a track's preview, carried as `previewURL` on
    /// Tidal rows so the preview UI (swipe action, menu item, progress fill)
    /// works as for other services; the player swaps it for a fresh
    /// `previewStreamURL` when tapped.
    public static func previewPlaceholderURL(trackID: String) -> URL? {
        URL(string: "\(previewScheme)://track/\(trackID)")
    }

    /// The track id in a `previewPlaceholderURL`, or nil for any other URL.
    public static func trackID(fromPreviewPlaceholder url: URL) -> String? {
        guard url.scheme == previewScheme, url.host == "track" else { return nil }
        let id = url.lastPathComponent
        return id.isEmpty || id == "/" ? nil : id
    }

    private static let previewScheme = "tidal-preview"

    /// Tracks Tidal considers similar to `id` — what backs its own "track
    /// radio" — with artwork and artists. Two pages (40), which is plenty for
    /// a Find Similar list.
    public func similarTracks(id: String) async -> [TidalTrackResource] {
        await relationshipPages(
            path: "/v2/tracks/\(id)/relationships/similarTracks",
            include: "similarTracks.albums.coverArt,similarTracks.artists",
            maxPages: 2
        ) { page in
            page.resources.filter { $0.type == "tracks" }.compactMap { track in
                let album = page.related(track.relationships?.albums).first.flatMap { page.album($0) }
                return page.track(track, album: album)
            }
        }
    }

    /// Artists Tidal considers similar to `id`, with their pictures.
    public func similarArtists(id: String) async -> [TidalArtistResource] {
        await relationshipPages(
            path: "/v2/artists/\(id)/relationships/similarArtists",
            include: "similarArtists.profileArt",
            maxPages: 1
        ) { page in
            page.resources.compactMap { page.artist($0) }
        }
    }

    /// Fetches a standalone relationship endpoint page by page, following the
    /// cursor for up to `maxPages`.
    private func relationshipPages<T>(
        path: String,
        include: String,
        maxPages: Int,
        map: (TidalRelationshipPage) -> [T]
    ) async -> [T] {
        var results: [T] = []
        var cursor: String?
        for _ in 0..<maxPages {
            let extra = cursor.map { [URLQueryItem(name: "page[cursor]", value: $0)] } ?? []
            guard let url = Self.url(path: path, include: include, extra: extra),
                  let page: TidalRelationshipPage = try? await loadAuthorized(url) else { break }
            results += map(page)
            cursor = page.links?.meta?.nextCursor
            if cursor == nil { break }
        }
        return results
    }

    /// Everything the artist has released — albums, EPs and singles — newest
    /// first. Tidal pages this at 20 and sorts by date, so a prolific artist's
    /// first page can be all singles; follow the cursor for the rest. Tidal
    /// also lists each quality variant (stereo, Dolby Atmos, hi-res) as its
    /// own release, which is collapsed to one.
    public func artistAlbums(id: String) async -> [TidalAlbumResource] {
        guard let url = Self.url(path: "/v2/artists/\(id)", include: "albums.coverArt,profileArt"),
              let document: TidalDocument = try? await loadAuthorized(url),
              let artist = document.artist(document.data) else { return [] }

        var albums = document.related(document.data.relationships?.albums)
            .compactMap { document.album($0, fallbackArtists: [artist]) }
        var cursor = document.data.relationships?.albums?.links?.meta?.nextCursor
        var pages = 0
        while let next = cursor, pages < Self.maxRelationshipPages {
            guard let pageURL = Self.url(
                path: "/v2/artists/\(id)/relationships/albums",
                include: "albums.coverArt",
                extra: [URLQueryItem(name: "page[cursor]", value: next)]
            ),
                  let page: TidalRelationshipPage = try? await loadAuthorized(pageURL) else { break }
            albums += page.resources.compactMap { page.album($0, fallbackArtists: [artist]) }
            cursor = page.links?.meta?.nextCursor
            pages += 1
        }
        return Self.collapsingVariants(albums)
    }

    /// Keeps one release per title, date and length. Prefers a stereo variant
    /// over Dolby Atmos — Sonos plays Atmos-only releases on few speakers.
    static func collapsingVariants(_ albums: [TidalAlbumResource]) -> [TidalAlbumResource] {
        struct Key: Hashable {
            let title: String
            let releaseDate: String?
            let tracks: Int?
        }
        func isAtmos(_ album: TidalAlbumResource) -> Bool {
            album.mediaMetadata?.contains("DOLBY_ATMOS") ?? false
        }
        var chosen: [Key: Int] = [:]
        var result: [TidalAlbumResource] = []
        for album in albums {
            let key = Key(title: album.title.lowercased(), releaseDate: album.releaseDate, tracks: album.numberOfTracks)
            if let index = chosen[key] {
                if isAtmos(result[index]), !isAtmos(album) { result[index] = album }
            } else {
                chosen[key] = result.count
                result.append(album)
            }
        }
        return result
    }

    public func artist(with id: String) async -> TidalArtistResource? {
        guard let url = Self.url(path: "/v2/artists/\(id)", include: "profileArt"),
              let document: TidalDocument = try? await loadAuthorized(url) else { return nil }
        return document.artist(document.data)
    }

    /// A v2 URL. Catalog paths take the country whose catalog to answer
    /// from; the user's own resources (`userCollection…`) take a `locale`
    /// instead and no country, since the account already has one.
    private static func url(path: String, include: String, extra: [URLQueryItem] = [], userResource: Bool = false) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openapi.tidal.com"
        components.path = path
        let place = userResource
            ? URLQueryItem(name: "locale", value: Locale.current.identifier(.bcp47))
            : URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US")
        components.queryItems = [place]
            + (include.isEmpty ? [] : [URLQueryItem(name: "include", value: include)]) + extra
        return components.url
    }

    // MARK: The signed-in user's collection

    /// One page (20) of the signed-in user's collection, newest addition
    /// first, and the cursor for the next. Throws `AuthError.missingToken`
    /// with nobody signed in: these are the user's own resources, which the
    /// app's token can't read.
    public func collectionTracks(cursor: String? = nil) async throws -> ([TidalTrackResource], String?) {
        let page = try await collectionPage("userCollectionTracks", include: "items,items.albums.coverArt,items.artists", cursor: cursor)
        let tracks = page.resources
            .filter { $0.type == "tracks" }
            .compactMap { track in
                let album = page.related(track.relationships?.albums).first.flatMap { page.album($0) }
                return page.track(track, album: album)
            }
        return (tracks, page.links?.meta?.nextCursor)
    }

    public func collectionAlbums(cursor: String? = nil) async throws -> ([TidalAlbumResource], String?) {
        let page = try await collectionPage("userCollectionAlbums", include: "items,items.coverArt,items.artists", cursor: cursor)
        return (page.resources.compactMap { page.album($0) }, page.links?.meta?.nextCursor)
    }

    public func collectionArtists(cursor: String? = nil) async throws -> ([TidalArtistResource], String?) {
        let page = try await collectionPage("userCollectionArtists", include: "items,items.profileArt", cursor: cursor)
        return (page.resources.compactMap { page.artist($0) }, page.links?.meta?.nextCursor)
    }

    /// The user's playlists, their own and the ones they follow, out of any
    /// folders they're filed in (`FLAT`). Mixes and folders are left out.
    public func collectionPlaylists(cursor: String? = nil) async throws -> ([TidalPlaylistResource], String?) {
        let page = try await collectionPage(
            "userCollectionPlaylists",
            include: "items,items.coverArt",
            cursor: cursor,
            sort: "-lastModifiedAt",
            extra: [URLQueryItem(name: "collectionView", value: "FLAT")]
        )
        return (page.resources.compactMap { page.playlist($0) }, page.links?.meta?.nextCursor)
    }

    private func collectionPage(
        _ resource: String,
        include: String,
        cursor: String?,
        sort: String = "-addedAt",
        extra: [URLQueryItem] = []
    ) async throws -> TidalRelationshipPage {
        var query = extra + [URLQueryItem(name: "sort", value: sort)]
        if let cursor {
            query.append(URLQueryItem(name: "page[cursor]", value: cursor))
        }
        guard let url = Self.url(path: "/v2/\(resource)/me/relationships/items", include: include, extra: query, userResource: true) else {
            throw RequestError.status(0)
        }
        return try await loadAuthorized(url, asUser: true)
    }

    /// One page (20) of a playlist's tracks and the cursor for the next.
    /// This endpoint only accepts `items` (and paths under it) as includes —
    /// asking for the playlist's own `coverArt` failed the whole request.
    public func playlist(with id: String, cursor: String? = nil) async -> ([TidalTrackResource], String?)? {
        var extra: [URLQueryItem] = []
        if let cursor {
            extra.append(URLQueryItem(name: "page[cursor]", value: cursor))
        }
        guard let url = Self.url(
            path: "/v2/playlists/\(id)/relationships/items",
            include: "items.albums.coverArt,items.artists",
            extra: extra
        ),
              let page: TidalRelationshipPage = try? await loadAuthorized(url) else { return nil }
        let tracks = page.resources
            .filter { $0.type == "tracks" }
            .compactMap { track in
                let album = page.related(track.relationships?.albums).first.flatMap { page.album($0) }
                return page.track(track, album: album)
            }
        return (tracks, page.links?.meta?.nextCursor)
    }

    func getToken() async -> TidalTokenResponse? {
        guard let URL = URL(string: "https://auth.tidal.com/v1/oauth2/token") else { return nil }
        var request = URLRequest(url: URL)
        request.httpMethod = "POST"
        request.addValue("Basic NlhINER0MEZnR3gzVEhaNjp2U0szVW5Pc3libzcyRDB2Nlp0emlGSUVyVFZIa29IbGo0a0xWUmdKY3pBPQ==", forHTTPHeaderField: "Authorization")
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            let spotifySearch = try decoder.decode(TidalTokenResponse.self, from: data)
            return spotifySearch
        } catch {
            print(String(decoding: data, as: UTF8.self))
            return nil
        }
    }

    // MARK: Token

    private var currentToken: Token?
    private var refreshTask: Task<Token, Error>?

    enum AuthError: Error {
        case missingToken
        case invalidToken
    }

    /// `asUser` is for the user's own resources: it goes out with the
    /// signed-in user's token or not at all. Everything else goes out as the
    /// user when someone is signed in, and as the app otherwise.
    func loadAuthorized<T: Decodable>(_ url: URL, asUser: Bool = false, allowRetry: Bool = true) async throws -> T {
        let (request, signedIn) = try await authorizedRequest(from: url, asUser: asUser)
        let (data, urlResponse) = try await session.data(for: request)
        let status = (urlResponse as? HTTPURLResponse)?.statusCode ?? 200

        switch status {
        case 401:
            // Retry once with a fresh token: the client's is fetched again,
            // and the user's is refreshed by the Auth module when it has
            // expired.
            guard allowRetry else { throw AuthError.invalidToken }
            if !signedIn { _ = try await refreshToken() }
            return try await loadAuthorized(url, asUser: asUser, allowRetry: false)
        case 429:
            // Rate limited — artist pages make several paged requests in a
            // row. Wait as asked (capped, so a view never stalls) and retry once.
            guard allowRetry else { throw RequestError.status(status) }
            let retryAfter = (urlResponse as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Retry-After")
                .flatMap(Double.init) ?? 1
            try await Task.sleep(for: .seconds(min(max(retryAfter, 0.5), 3)))
            return try await loadAuthorized(url, asUser: asUser, allowRetry: false)
        case 200..<300:
            break
        default:
            // An error body isn't the resource — don't try to decode it.
            throw RequestError.status(status)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            print("Tidal: couldn't decode \(T.self) from \(url.path): \(error)")
            throw error
        }
    }

    enum RequestError: Error {
        case status(Int)
    }

    /// The request with its bearer token, and whether that token is the
    /// signed-in user's.
    private func authorizedRequest(from url: URL, asUser: Bool) async throws -> (URLRequest, Bool) {
        var urlRequest = URLRequest(url: url)
        if let user = await Self.userToken?() {
            urlRequest.setValue("Bearer \(user)", forHTTPHeaderField: "Authorization")
            return (urlRequest, true)
        }
        guard !asUser else { throw AuthError.missingToken }
        let token = try await validToken()
        urlRequest.setValue("Bearer \(token.id)", forHTTPHeaderField: "Authorization")
        return (urlRequest, false)
    }

    /// The signed-in user's access token, or nil with nobody signed in. The
    /// app sets it from TIDAL's Auth module (`TidalAccount`), which keeps the
    /// token fresh, so it is asked for every request rather than kept.
    /// While it answers, requests go out as the user: their country's
    /// catalog, and their collection. The app's own token covers the
    /// catalog otherwise.
    public static var userToken: (@Sendable () async -> String?)?

    func validToken() async throws -> Token {
        if let handle = refreshTask {
            return try await handle.value
        }

        guard let token = currentToken else {
            return try await refreshToken()
//            throw AuthError.missingToken
        }

        if token.isValid {
            return token
        }

        return try await refreshToken()
    }

    func refreshToken() async throws -> Token {
        if let refreshTask = refreshTask {
            return try await refreshTask.value
        }

        let task = Task { () throws -> Token in
            defer { refreshTask = nil }

            guard let response = await getToken() else {
                throw AuthError.missingToken
            }

            let newToken = Token(validUntil: Date.now.addingTimeInterval(TimeInterval(response.expiresIn)), id: response.accessToken)
            currentToken = newToken
            return newToken
        }

        self.refreshTask = task
        return try await task.value
    }
}

extension TidalAPI {
    struct Token {
        let validUntil: Date
        let id: String
        var isValid: Bool { Date.now < validUntil }
    }
}

// MARK: - Documents

/// A single-resource JSON:API document from Tidal's v2 API (`/albums/{id}`,
/// `/artists/{id}`, `/tracks/{id}`) plus the resources it `include`d, with
/// helpers that resolve relationships against them.
///
/// Artwork is its own resource type in v2: an album's cover and an artist's
/// picture hang off `coverArt` / `profileArt` relationships to `artworks`,
/// not off the album or artist attributes.
struct TidalDocument: Codable, TidalIncludes {
    let data: TidalIncluded
    let included: [TidalIncluded]?
}

/// Anything carrying `included` resources: resolves relationships against
/// them and maps them to the Tidal resource models.
protocol TidalIncludes {
    var included: [TidalIncluded]? { get }
}

extension TidalIncludes {

    /// The included resources a relationship points at, in the
    /// relationship's order (which is the meaningful one — running order,
    /// popularity — while `included` is sorted by id).
    func related(_ relationship: TidalRelationship?) -> [TidalIncluded] {
        guard let references = relationship?.data else { return [] }
        return references.compactMap { reference in
            included?.first { $0.id == reference.id && $0.type == reference.type }
        }
    }

    func artwork(_ relationship: TidalRelationship?) -> [TidalImage] {
        related(relationship).first?.attributes?.tidalImages ?? []
    }

    func artist(_ item: TidalIncluded) -> TidalArtistResource? {
        guard item.type == "artists", let attributes = item.attributes else { return nil }
        return TidalArtistResource(
            id: item.id,
            name: attributes.label,
            picture: artwork(item.relationships?.profileArt),
            main: true,
            tidalUrl: attributes.tidalURL,
            popularity: attributes.popularityRating
        )
    }

    func album(_ item: TidalIncluded, fallbackArtists: [TidalArtistResource] = []) -> TidalAlbumResource? {
        guard item.type == "albums", let attributes = item.attributes else { return nil }
        let artists = related(item.relationships?.artists).compactMap(artist)
        let cover = artwork(item.relationships?.coverArt)
        return TidalAlbumResource(
            id: item.id,
            barcodeId: attributes.barcodeId,
            title: attributes.label,
            artists: artists.isEmpty ? fallbackArtists : artists,
            duration: attributes.durationInSeconds,
            releaseDate: attributes.releaseDate,
            imageCover: cover.isEmpty ? nil : cover,
            numberOfVolumes: attributes.numberOfVolumes,
            numberOfTracks: attributes.numberOfItems,
            numberOfVideos: nil,
            copyright: nil,
            tidalUrl: attributes.tidalURL,
            properties: nil,
            mediaMetadata: attributes.mediaTags,
            isExplicit: attributes.isExplicit,
            popularity: attributes.popularityRating,
            albumType: attributes.albumType
        )
    }

    /// A playlist resource. Its id is the playlist's UUID, which is what the
    /// playlist endpoints and a speaker's playlist URI both take.
    func playlist(_ item: TidalIncluded) -> TidalPlaylistResource? {
        guard item.type == "playlists", let attributes = item.attributes else { return nil }
        return TidalPlaylistResource(
            id: item.id,
            name: attributes.label,
            description: attributes.description,
            numberOfTracks: attributes.numberOfItems,
            duration: attributes.durationInSeconds,
            imageUrls: artwork(item.relationships?.coverArt),
            tidalUrl: attributes.tidalURL
        )
    }

    func track(
        _ item: TidalIncluded,
        album: TidalAlbumResource?,
        fallbackArtists: [TidalArtistResource] = []
    ) -> TidalTrackResource? {
        guard item.type == "tracks", let attributes = item.attributes else { return nil }
        let artists = related(item.relationships?.artists).compactMap(artist)
        return TidalTrackResource(
            id: item.id,
            isrc: attributes.isrc,
            title: attributes.label,
            artists: artists.isEmpty ? fallbackArtists : artists,
            album: album,
            duration: attributes.durationInSeconds,
            releaseDate: attributes.releaseDate,
            imageCover: album?.imageCover,
            numberOfVolumes: nil,
            numberOfTracks: nil,
            numberOfVideos: nil,
            copyright: nil,
            tidalUrl: attributes.tidalURL,
            mediaMetadata: attributes.mediaTags,
            isExplicit: attributes.isExplicit,
            popularity: attributes.popularityRating
        )
    }
}

/// A page of a relationship fetched on its own
/// (`/albums/{id}/relationships/items?page[cursor]=…`): references in order,
/// the included resources, and the cursor for the page after.
struct TidalRelationshipPage: Codable, TidalIncludes {
    let data: [TidalRelationshipData]
    let included: [TidalIncluded]?
    let links: TidalLinks?

    /// The referenced resources, in page order.
    var resources: [TidalIncluded] {
        data.compactMap { reference in
            included?.first { $0.id == reference.id && $0.type == reference.type }
        }
    }
}
