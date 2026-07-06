import Foundation
import os
import SwiftyBeaver

@Observable
public final class PlexAPI {
    @ObservationIgnored public static var shared = PlexAPI()
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let decoder: JSONDecoder
    @ObservationIgnored private let parser = PlexParser()
    @ObservationIgnored private let logger = SwiftyBeaver.self

    // MARK: - Connection cache
    // `plexServer`, `resolvedBaseURL`, and `resolvedBaseURLByServer` are read
    // and written from concurrent tasks (parallel browse calls, the loadData
    // self-heal path, onboarding fan-out). They're guarded by `cacheLock` so
    // access is race-free while keeping `getBaseURL` synchronous. Never hold the
    // lock across an `await`.
    @ObservationIgnored private let cacheLock = OSAllocatedUnfairLock()
    @ObservationIgnored private var plexServer: PlexServer?
    @ObservationIgnored private var resolvedBaseURLByServer: [String: URL] = [:]

    private func withCacheLock<T>(_ body: () -> T) -> T {
        cacheLock.withLock(body)
    }

    private let authenticator: PlexAuthenticator
    
    @MainActor
    public var isAuthorized: Bool {
        authenticator.authToken != nil
    }

    public var serverID: String? {
        didSet {
            UserDefaults.standard.set(serverID, forKey: "com.clic.plexServer")
        }
    }
    
    public var librarySelectionID: String? {
        didSet {
            UserDefaults.standard.set(librarySelectionID, forKey: "com.clic.plexServer.library")
        }
    }

    @ObservationIgnored
    public var connectionPreference: ConnectionPreference {
        get {
            access(keyPath: \.connectionPreference)
            if let preference = UserDefaults.standard.string(forKey: "com.clic.plexServer.connectionPreference"), let connection = ConnectionPreference(rawValue: preference) {
                return connection
            }
            return ConnectionPreference.auto
        }
        set {
            withMutation(keyPath: \.connectionPreference) {
                UserDefaults.standard.set(newValue.rawValue, forKey: "com.clic.plexServer.connectionPreference")
            }
            // Drop the cached server + resolved connections so the next request
            // re-resolves against the newly chosen preference.
            withCacheLock {
                plexServer = nil
                resolvedBaseURL = nil
                resolvedBaseURLByServer.removeAll()
            }
        }
    }

    @ObservationIgnored
    var _connectionPreference: String?

    /// Best base URL for the selected server, resolved once (see
    /// `resolveBaseURL`) and reused for browse requests. Cleared when the
    /// connection preference or selected server changes. Guarded by `cacheLock`.
    @ObservationIgnored
    private var resolvedBaseURL: URL?

    public enum ConnectionPreference: String, CaseIterable {
        /// Hybrid: use the local connection when reachable (fast), otherwise
        /// fall back to remote. Resolved by racing the connections.
        case auto = "auto"
        case nonLocal = "nonLocal"
        case local = "local"

        public var displayName: String {
            switch self {
            case .auto:
                return "Automatic"
            case .local:
                return "Local Network"
            case .nonLocal:
                return "Remote Access"
            }
        }

        /// Short label for the segmented picker.
        public var shortName: String {
            switch self {
            case .auto:
                return "Auto"
            case .local:
                return "Local"
            case .nonLocal:
                return "Remote"
            }
        }

        public var description: String {
            switch self {
            case .auto:
                return "Uses your local network at home and remote access when you're away."
            case .local:
                return "Local network only — faster, but requires the same network."
            case .nonLocal:
                return "Remote access — works from anywhere, may be slower."
            }
        }
    }

    public init(authenticator: PlexAuthenticator = .shared,
                session: URLSession = .shared,
                decoder: JSONDecoder = JSONDecoder()) {
        self.authenticator = authenticator
        self.session = session
        self.decoder = decoder
        self.decoder.dateDecodingStrategy = .secondsSince1970

        // Optimize logging configuration
        let console = ConsoleDestination()
        console.format = "$C$L$c $M" // Simplified format for console
        
        let file = FileDestination()
        file.format = "$J"
        file.logFileMaxSize = (1 * 1024 * 1024)
        file.asynchronously = true // Async logging to avoid blocking
        
        // Only add destinations in debug builds to reduce overhead
        #if MUSICSEARCHKIT_VERBOSE_LOGGING
        logger.addDestination(console)
        logger.addDestination(file)
        #endif
        
        self.librarySelectionID = UserDefaults.standard.string(forKey: "com.clic.plexServer.library")
        self.serverID = UserDefaults.standard.string(forKey: "com.clic.plexServer")
    }

    public func rateTrack(ratingKey: String, rating: Int) async -> Bool {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken,
              var rateURL = getBaseURL(for: plexServer)?.appending(path: ":/rate") else {
            return false
        }
        rateURL.append(queryItems: [
            URLQueryItem(name: "key", value: ratingKey),
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
            URLQueryItem(name: "rating", value: "\(rating)")
        ])
        var request = URLRequest(url: rateURL)
        request.httpMethod = "PUT"
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    public func getTrackRating(ratingKey: String) async -> Double? {
        guard let song = await lookupPlexSong(key: ratingKey) else { return nil }
        return song.metadata?.first?.userRating
    }

    // MARK: - Playlist Management

    /// The library item uri Plex expects when seeding or adding tracks to a playlist.
    private func libraryItemURI(machineIdentifier: String, ratingKey: String) -> String {
        "server://\(machineIdentifier)/com.plexapp.plugins.library/library/metadata/\(ratingKey)"
    }

    /// Creates a new audio playlist, optionally seeded with a single track.
    /// - Returns: The new playlist's ratingKey, or `nil` on failure.
    public func createPlaylist(title: String, trackRatingKey: String? = nil) async -> String? {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken,
              let machineIdentifier = plexServer.clientIdentifier,
              var url = getBaseURL(for: plexServer)?.appending(path: "playlists") else {
            return nil
        }
        var queryItems = [
            URLQueryItem(name: "type", value: "audio"),
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "smart", value: "0")
        ]
        if let trackRatingKey {
            queryItems.append(URLQueryItem(name: "uri", value: libraryItemURI(machineIdentifier: machineIdentifier, ratingKey: trackRatingKey)))
        }
        url.append(queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        let container = try? decoder.decode(PlexContainer<PlexUserPlaylistContainer>.self, from: data)
        return container?.mediaContainer.metadata.first?.ratingKey
    }

    /// Adds a track to an existing playlist.
    public func addToPlaylist(playlistRatingKey: String, trackRatingKey: String) async -> Bool {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken,
              let machineIdentifier = plexServer.clientIdentifier,
              var url = getBaseURL(for: plexServer)?.appending(path: "playlists/\(playlistRatingKey)/items") else {
            return false
        }
        url.append(queryItems: [
            URLQueryItem(name: "uri", value: libraryItemURI(machineIdentifier: machineIdentifier, ratingKey: trackRatingKey))
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    /// Moves a playlist item after another item, or to the front when `afterItemID` is nil.
    public func movePlaylistItem(playlistRatingKey: String, playlistItemID: String, afterItemID: String?) async -> Bool {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken,
              var url = getBaseURL(for: plexServer)?.appending(path: "playlists/\(playlistRatingKey)/items/\(playlistItemID)/move") else {
            return false
        }
        if let afterItemID {
            url.append(queryItems: [URLQueryItem(name: "after", value: afterItemID)])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    /// Removes a single item (identified by its playlist item id) from a playlist.
    public func removeFromPlaylist(playlistRatingKey: String, playlistItemID: String) async -> Bool {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken,
              let url = getBaseURL(for: plexServer)?.appending(path: "playlists/\(playlistRatingKey)/items/\(playlistItemID)") else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    /// Deletes a playlist entirely.
    public func deletePlaylist(ratingKey: String) async -> Bool {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken,
              let url = getBaseURL(for: plexServer)?.appending(path: "playlists/\(ratingKey)") else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    public func search(for query: String, limit: Int = 50) async -> PlexResults? {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken else {
            logger.info("No server")
            return nil
        }

        guard var search = getBaseURL(for: plexServer)?.appending(path: "hubs/search") else {
            logger.warning("Token: \(token)")
            logger.warning("Plex invalid url \(plexServer.name)")
            return nil
        }
        
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        search.append(queryItems: queryItems)
        
        var request = URLRequest(url: search)
        request.httpMethod = "GET"
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = await loadData(for: request) else {
            logger.warning("Search request failed \(String(describing: request.url?.absoluteString))")
            return nil
        }

        #if MUSICSEARCHKIT_VERBOSE_LOGGING
        let xml = String(decoding: data, as: UTF8.self)
        logger.info("\(xml)")
        #endif
        
        return parser.parseXML(xmlData: data, plexServer: plexServer, connectionPreference: connectionPreference, baseURL: getBaseURL(for: plexServer))
    }

    /// Batch media lookup, keyed by ratingKey. Some servers omit the `Media`
    /// element (codec/bitrate) from `/hubs/search` responses, so search
    /// results are enriched from `/library/metadata/{id,id,...}` — one
    /// request for all tracks — which always includes it.
    public func trackMedia(ratingKeys: [String]) async -> [String: PlexMedia] {
        guard !ratingKeys.isEmpty,
              let plexServer = await getPlexServer(),
              let token = plexServer.accessToken,
              let url = getBaseURL(for: plexServer)?.appending(path: "library/metadata/\(ratingKeys.joined(separator: ","))") else {
            return [:]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = await loadData(for: request),
              let container = try? decoder.decode(PlexContainer<PlexBatchMetadata>.self, from: data).mediaContainer else {
            return [:]
        }

        var mediaByKey: [String: PlexMedia] = [:]
        for item in container.metadata ?? [] {
            if let media = item.media?.first {
                mediaByKey[item.ratingKey] = media
            }
        }
        return mediaByKey
    }

    /// Minimal container for the batch metadata endpoint: unlike
    /// `PlexSongItem`, no `librarySectionID`/`librarySectionTitle` — a batch
    /// spanning several libraries omits the container-level section fields.
    private struct PlexBatchMetadata: Codable {
        let metadata: [PlexMetadata]?
        enum CodingKeys: String, CodingKey {
            case metadata = "Metadata"
        }
    }

    public func playlists() async -> [PlexUserPlaylist] {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken else {
            return []
        }
        
        #if MUSICSEARCHKIT_VERBOSE_LOGGING
        logger.info(plexServer)
        #endif

        guard var playlistsURL = getBaseURL(for: plexServer)?.appending(path: "playlists") else { return [] }
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "playlistType", value: "audio")
        ]
        playlistsURL.append(queryItems: queryItems)

        guard let playlistContainer: PlexContainer<PlexUserPlaylistContainer> = await loadAuthorized(playlistsURL) else {
            return []
        }

        var playlists = playlistContainer.mediaContainer.metadata
        guard let id = plexServer.clientIdentifier else { return [] }

        for index in playlists.indices {
            playlists[index].sonosID = "\(id)%3A3%3A\(playlists[index].ratingKey)"
            guard let composite = playlists[index].composite else { continue }
            playlists[index].thumbImageURL = getBaseURL(for: plexServer)?.appending(path:  composite).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
        }

        return playlists
    }
    
    public enum AlbumSortOrder {
        case titleAscending
        case titleDescending
        
        var queryValue: String {
            switch self {
            case .titleAscending:
                return "titleSort:asc"
            case .titleDescending:
                return "titleSort:desc"
            }
        }
    }
    
    public func artists(
        sortOrder: AlbumSortOrder = .titleAscending,
        offset: Int = 0,
        limit: Int = 100
    ) async -> [PlexMetadata] {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken else {
            return []
        }
        
        #if MUSICSEARCHKIT_VERBOSE_LOGGING
        logger.info(plexServer)
        #endif
        
        // Get and cache music library section if needed
        if librarySelectionID == nil {
            librarySelectionID = await getMusicLibrarySection()
        }
        
        guard let sectionKey = librarySelectionID,
              var albumURL = getBaseURL(for: plexServer)?.appending(path: "/library/sections/\(sectionKey)/all") else {
            return []
        }
        
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: "8"),
            URLQueryItem(name: "sort", value: sortOrder.queryValue),
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(limit)"),
            URLQueryItem(name: "X-Plex-Container-Start", value: "\(offset)")
        ]
        albumURL.append(queryItems: queryItems)

        guard let artistsContainer: PlexContainer<PlexArtistContainer> = await loadAuthorized(albumURL) else {
            return []
        }

        guard var artists = artistsContainer.mediaContainer.metadata else { return [] }
        guard let id = plexServer.clientIdentifier else { return [] }

        for index in artists.indices {
            artists[index].sonosID = "\(id)%3A3%3A\(artists[index].ratingKey)"
            guard let thumb = artists[index].thumb else { continue }
            artists[index].thumbImageURL = getBaseURL(for: plexServer)?.appending(path: thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
        }

        return artists
    }

    
    public func albums(
        sortOrder: AlbumSortOrder = .titleAscending,
        offset: Int = 0,
        limit: Int = 100
    ) async -> [PlexAlbumItem] {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken else {
            return []
        }
        
        #if MUSICSEARCHKIT_VERBOSE_LOGGING
        logger.info(plexServer)
        #endif
        
        // Get and cache music library section if needed
        if librarySelectionID == nil {
            librarySelectionID = await getMusicLibrarySection()
        }
        
        guard let sectionKey = librarySelectionID,
              var albumURL = getBaseURL(for: plexServer)?.appending(path: "/library/sections/\(sectionKey)/all") else {
            return [] 
        }
        
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: "9"),
            URLQueryItem(name: "sort", value: sortOrder.queryValue),
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(limit)"),
            URLQueryItem(name: "X-Plex-Container-Start", value: "\(offset)")
        ]
        albumURL.append(queryItems: queryItems)

        guard let playlistContainer: PlexContainer<PlexAlbumContainer> = await loadAuthorized(albumURL) else {
            return []
        }

        guard var playlists = playlistContainer.mediaContainer.metadata else { return [] }
        guard let id = plexServer.clientIdentifier else { return [] }

        for index in playlists.indices {
            guard let ratingKey = playlists[index].ratingKey else { continue }
            playlists[index].sonosID = "\(id)%3A3%3A\(ratingKey)"
            guard let thumb = playlists[index].thumb else { continue }
            playlists[index].thumbImageURL = getBaseURL(for: plexServer)?.appending(path: thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
        }

        return playlists
    }
    
    public func songs(
        sortOrder: AlbumSortOrder = .titleAscending,
        offset: Int = 0,
        limit: Int = 100
    ) async -> [PlexMetadata] {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken else {
            return []
        }
        
        #if MUSICSEARCHKIT_VERBOSE_LOGGING
        logger.info(plexServer)
        #endif
        
        // Get and cache music library section if needed
        if librarySelectionID == nil {
            librarySelectionID = await getMusicLibrarySection()
        }
        
        guard let sectionKey = librarySelectionID,
              var albumURL = getBaseURL(for: plexServer)?.appending(path: "/library/sections/\(sectionKey)/all") else {
            return []
        }
        
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: "10"),
            URLQueryItem(name: "sort", value: sortOrder.queryValue),
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(limit)"),
            URLQueryItem(name: "X-Plex-Container-Start", value: "\(offset)")
        ]
        albumURL.append(queryItems: queryItems)

        guard let songContainer: PlexContainer<PlexSongItem> = await loadAuthorized(albumURL) else {
            return []
        }

        guard var songs = songContainer.mediaContainer.metadata else { return [] }
        guard let id = plexServer.clientIdentifier else { return [] }

        for index in songs.indices {
            songs[index].sonosID = "\(id)%3A3%3A\(songs[index].ratingKey)"
            songs[index].streamURL = streamURL(for: songs[index], server: plexServer, token: token)
            guard let thumb = songs[index].thumb else { continue }
            songs[index].thumbImageURL = getBaseURL(for: plexServer)?.appending(path: thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
        }

        return songs
    }

    private func getMusicLibrarySection() async -> String? {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken else {
            return nil
        }

        guard let sectionsURL = getBaseURL(for: plexServer)?.appending(path: "library/sections") else {
            return nil
        }

        var request = URLRequest(url: sectionsURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            let container = try decoder.decode(PlexContainer<PlexLibrarySectionContainer>.self, from: data)
            let musicSection = container.mediaContainer.Directory
                .sorted(by: { $0.key < $1.key })
                .first { $0.type == "artist" }
            return musicSection?.key
        } catch {
            logger.error(error)
            return nil
        }
    }
    
    /// Picks the fastest reachable base URL for a server by racing its candidate
    /// connections (local + remote) concurrently and using whichever responds
    /// first — so we use the LAN connection at home and remote when away,
    /// without paying a sequential timeout penalty. Falls back to the
    /// connection-preference URL if no probe succeeds.
    func resolveBaseURL(for server: PlexServer, forceRefresh: Bool = false) async -> URL? {
        // Reuse a previously-raced result for this server unless a caller forces
        // a refresh (loadData does this when a cached connection went stale).
        let cacheKey = server.clientIdentifier
        if !forceRefresh, let cacheKey, let cached = withCacheLock({ resolvedBaseURLByServer[cacheKey] }) {
            return cached
        }

        let fallback = server.baseURL(preferring: connectionPreference)
        guard let token = server.accessToken else { return fallback }

        // Candidate connections to probe, per preference:
        //  - .local: local only
        //  - .nonLocal: remote only
        //  - .auto: race local (fast at home) against remote (works anywhere)
        let candidateStrings: [String]
        switch connectionPreference {
        case .local:    candidateStrings = server.localURIs
        case .nonLocal: candidateStrings = server.nonLocalURIs
        case .auto:     candidateStrings = server.localURIs + server.nonLocalURIs
        }
        let candidates = candidateStrings.compactMap { URL(string: $0) }
        guard !candidates.isEmpty else { return fallback }

        let session = self.session
        let winner = await withTaskGroup(of: URL?.self) { group -> URL? in
            for url in candidates {
                group.addTask {
                    var request = URLRequest(url: url.appending(path: "identity"))
                    request.timeoutInterval = 4
                    request.addValue("application/json", forHTTPHeaderField: "Accept")
                    request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
                    request.addValue(token, forHTTPHeaderField: "X-Plex-Token")
                    guard let (_, response) = try? await session.data(for: request),
                          let http = response as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode) else { return nil }
                    return url
                }
            }
            // Return the first connection to respond, then cancel the rest.
            for await result in group {
                if let url = result {
                    group.cancelAll()
                    return url
                }
            }
            return nil
        }

        // Cache only a real probe winner, so a failed race re-probes next time.
        if let cacheKey, let winner {
            withCacheLock { resolvedBaseURLByServer[cacheKey] = winner }
        }
        return winner ?? fallback
    }

    public func getMusicLibraries(server: PlexServer) async -> [PlexLibrarySection] {
        guard let token = server.accessToken else {
            return []
        }

        guard let sectionsURL = (await resolveBaseURL(for: server))?.appending(path: "library/sections") else {
            return []
        }

        var request = URLRequest(url: sectionsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = try? await session.data(for: request) else {
            return []
        }
        
        #if MUSICSEARCHKIT_VERBOSE_LOGGING
        logger.info(String(decoding: data, as: UTF8.self))
        #endif
        
        do {
            let container = try decoder.decode(PlexContainer<PlexLibrarySectionContainer>.self, from: data)
            #if MUSICSEARCHKIT_VERBOSE_LOGGING
            logger.info(container)
            #endif
            let libraries = container.mediaContainer.Directory
                .sorted(by: { $0.key < $1.key })
                .filter { $0.type == "artist" }
            return libraries
        } catch {
            logger.error(error)
            return []
        }
    }

    /// Fetches a handful of artists (with resolved artwork URLs) from a
    /// specific library section on a specific server. Unlike `artists()`, this
    /// doesn't depend on the currently-selected server/library — used to preview
    /// libraries (e.g. onboarding) before one is chosen.
    public func getArtists(server: PlexServer, sectionKey: String, limit: Int = 12) async -> [PlexMetadata] {
        guard let token = server.accessToken,
              let base = await resolveBaseURL(for: server) else {
            return []
        }

        var url = base.appending(path: "/library/sections/\(sectionKey)/all")
        url.append(queryItems: [
            URLQueryItem(name: "type", value: "8"), // 8 = artist
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(limit)"),
            URLQueryItem(name: "X-Plex-Container-Start", value: "0")
        ])

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = try? await session.data(for: request) else {
            return []
        }

        do {
            let container = try decoder.decode(PlexContainer<PlexArtistContainer>.self, from: data)
            guard var artists = container.mediaContainer.metadata else { return [] }
            for index in artists.indices {
                guard let thumb = artists[index].thumb else { continue }
                artists[index].thumbImageURL = base
                    .appending(path: thumb)
                    .appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
            }
            return artists
        } catch {
            logger.error(error)
            return []
        }
    }

    public func getMusicLibraries() async -> [PlexLibrarySection] {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken else {
            return []
        }

        guard let sectionsURL = getBaseURL(for: plexServer)?.appending(path: "library/sections") else {
            return []
        }

        var request = URLRequest(url: sectionsURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = try? await session.data(for: request) else {
            return []
        }
        
        #if MUSICSEARCHKIT_VERBOSE_LOGGING
        logger.info(String(decoding: data, as: UTF8.self))
        #endif
        
        do {
            let container = try decoder.decode(PlexContainer<PlexLibrarySectionContainer>.self, from: data)
            #if MUSICSEARCHKIT_VERBOSE_LOGGING
            logger.info(container)
            #endif
            let libraries = container.mediaContainer.Directory
                .sorted(by: { $0.key < $1.key })
                .filter { $0.type == "artist" }
            return libraries
        } catch {
            logger.error(error)
            return []
        }
    }
  
    public func lookupPlexSong(key: String) async -> PlexSongItem? {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken else {
            return nil
        }

        guard let songURL = getBaseURL(for: plexServer)?.appending(path: "library/metadata/\(key)") else {
            return nil
        }
        
        var request = URLRequest(url: songURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            let mediaContainer = try decoder.decode(PlexContainer<PlexSongItem>.self, from: data).mediaContainer
            return PlexSongItem(
                size: mediaContainer.size,
                allowSync: mediaContainer.allowSync,
                librarySectionID: mediaContainer.librarySectionID,
                librarySectionTitle: mediaContainer.librarySectionTitle,
                metadata: await enrichMetadata(metadata: mediaContainer.metadata)
            )
        } catch {
            #if MUSICSEARCHKIT_VERBOSE_LOGGING
            print(error)
            #endif
            return nil
        }
    }

    public func lookupAlbum(key: String) async -> PlexLibraryItem? {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken,
              let id = plexServer.clientIdentifier else {
            return nil
        }

        guard let albumURL = getBaseURL(for: plexServer)?.appending(path: "library/metadata/\(key)/children") else { return nil }
        var request = URLRequest(url: albumURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            let container = try decoder.decode(PlexContainer<PlexLibraryItem>.self, from: data).mediaContainer
            var thumbImageURL: URL? = nil
            if let thumb = container.thumb {
                thumbImageURL = getBaseURL(for: plexServer)?.appending(path: thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
            }
            return PlexLibraryItem(
                size: container.size,
                allowSync: container.allowSync,
                art: container.art,
                grandparentRatingKey: container.grandparentRatingKey,
                grandparentThumb: container.grandparentThumb,
                grandparentTitle: container.grandparentTitle,
                identifier: container.identifier,
                key: container.key,
                librarySectionID: container.librarySectionID,
                librarySectionTitle: container.librarySectionTitle,
                librarySectionUUID: container.librarySectionUUID,
                mediaTagPrefix: container.mediaTagPrefix,
                mediaTagVersion: container.mediaTagVersion,
                nocache: container.nocache,
                parentIndex: container.parentIndex,
                parentTitle: container.parentTitle,
                parentYear: container.parentYear,
                summary: container.summary,
                thumb: container.thumb,
                title1: container.title1,
                title2: container.title2,
                viewGroup: container.viewGroup,
                metadata: [],
                sonosID: "\(id)%3A3%3A\(container.key)",
                thumbImageURL: thumbImageURL
            )
        } catch {
            #if MUSICSEARCHKIT_VERBOSE_LOGGING
            print(error)
            #endif
            return nil
        }
    }

    public func lookupAlbumTracks(key: String) async -> PlexLibraryItem? {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken else {
            return nil
        }

        guard let albumURL = getBaseURL(for: plexServer)?.appending(path: "library/metadata/\(key)/children") else { return nil }
        var request = URLRequest(url: albumURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            let container = try decoder.decode(PlexContainer<PlexLibraryItem>.self, from: data).mediaContainer
            return PlexLibraryItem(
                size: container.size,
                allowSync: container.allowSync,
                art: container.art,
                grandparentRatingKey: container.grandparentRatingKey,
                grandparentThumb: container.grandparentThumb,
                grandparentTitle: container.grandparentTitle,
                identifier: container.identifier,
                key: container.key,
                librarySectionID: container.librarySectionID,
                librarySectionTitle: container.librarySectionTitle,
                librarySectionUUID: container.librarySectionUUID,
                mediaTagPrefix: container.mediaTagPrefix,
                mediaTagVersion: container.mediaTagVersion,
                nocache: container.nocache,
                parentIndex: container.parentIndex,
                parentTitle: container.parentTitle,
                parentYear: container.parentYear,
                summary: container.summary,
                thumb: container.thumb,
                title1: container.title1,
                title2: container.title2,
                viewGroup: container.viewGroup,
                metadata: await enrichMetadata(metadata: container.metadata)
            )
        } catch {
            #if MUSICSEARCHKIT_VERBOSE_LOGGING
            print(error)
            #endif
            return nil
        }
    }

    public func lookupPlaylist(key: String, type: PlexMediaType, ascending: Bool, offset: Int = 0) async -> PlexPlaylistItem? {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken else {
            return nil
        }

        guard var playlistURL = getBaseURL(for: plexServer)?.appending(path: "playlists/\(key)/items") else { return nil }
        
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: type.rawValue.description),
            URLQueryItem(name: "sort", value: ascending ? "titleSort:asc" : "titleSort:desc"),
        ]
        
        playlistURL.append(queryItems: queryItems)

        var request = URLRequest(url: playlistURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.addValue("\(offset)", forHTTPHeaderField: "X-Plex-Container-Start")
        request.addValue("200", forHTTPHeaderField: "X-Plex-Container-Size")
       

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            let mediaContainer = try decoder.decode(PlexContainer<PlexPlaylistItem>.self, from: data).mediaContainer
            return PlexPlaylistItem(
                size: mediaContainer.size,
                totalSize: mediaContainer.totalSize,
                ratingKey: mediaContainer.ratingKey,
                duration: mediaContainer.duration,
                title: mediaContainer.title,
                metadata: await enrichMetadata(metadata: mediaContainer.metadata)
            )
        } catch {
            #if MUSICSEARCHKIT_VERBOSE_LOGGING
            print(error)
            #endif
            return nil
        }
    }
    
    public func lookupPlaylist(key: String) async -> PlexUserPlaylist? {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken else {
            return nil
        }
        guard let playlistURL = getBaseURL(for: plexServer)?.appending(path: "playlists/\(key)") else { return nil }
        guard let playlistContainer: PlexContainer<PlexUserPlaylistContainer> = await loadAuthorized(playlistURL) else {
            return nil
        }

        var playlists = playlistContainer.mediaContainer.metadata
        guard let id = plexServer.clientIdentifier else { return nil }

        for index in playlists.indices {
            playlists[index].sonosID = "\(id)%3A3%3A\(playlists[index].ratingKey)"
            guard let composite = playlists[index].composite else { continue }
            playlists[index].thumbImageURL = getBaseURL(for: plexServer)?.appending(path:  composite).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
        }

        return playlists.first
    }

    public func lookupArtist(key: String) async -> PlexMetadata? {
        guard let plexServer = await getPlexServer(),
              let artistURL = getBaseURL(for: plexServer)?.appending(path: "library/metadata/\(key)"),
              let id = plexServer.clientIdentifier,
              let token = plexServer.accessToken else {
            return nil
        }

        guard let playlistContainer: PlexContainer<PlexArtistContainer> = await loadAuthorized(artistURL) else {
            return nil
        }

        guard var artist = playlistContainer.mediaContainer.metadata?.first else { return nil }

        artist.sonosID = "\(id)%3A3%3A\(artist.ratingKey)"
        if let thumb = artist.thumb {
            artist.thumbImageURL = getBaseURL(for: plexServer)?.appending(path: thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
        }
        return artist
    }

    public func getArtistAlbums(key: String) async -> [PlexAlbumHub]? {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken else {
            return nil
        }

        guard var artistURL = getBaseURL(for: plexServer)?.appending(path: "library/metadata/\(key)") else {
            return nil
        }
        
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "includeRelated", value: "1"),
            URLQueryItem(name: "includeRelatedCount", value: "999"),
            URLQueryItem(name: "excludeFields", value: "art,guid,lastRatedAt,loudnessAnalysisVersion,musicAnalysisVersion,parentGuid,parentKey,parentThumb,skipCount,studio,summary,updatedAt,viewCount"),
            URLQueryItem(name: "excludeElements", value: "Country,Director,Guid,Image,Location,Mood,Similar,Style,UltraBlurColors")
        ]
        artistURL.append(queryItems: queryItems)

        var request = URLRequest(url: artistURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, urlResponse) = try? await session.data(for: request) else {
            return nil
        }
        
        if let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 401 {
            // MARK: Reset
            Task { @MainActor in
                authenticator.authToken = nil
                serverID = nil
            }
            return nil
        }
        
        #if MUSICSEARCHKIT_VERBOSE_LOGGING
        let json = String(decoding: data, as: UTF8.self)
        logger.info("\(json)")
        #endif
        
        do {
            let container = try decoder.decode(PlexContainer<PlexArtistAlbumsContainer>.self, from: data)
            guard let artistMetadata = container.mediaContainer.metadata?.first,
                  let related = artistMetadata.related,
                  let hubs = related.hub else {
                return []
            }
            
            // Enrich the album metadata with Sonos IDs and image URLs
            var enrichedHubs = hubs
            guard let clientID = plexServer.clientIdentifier else { return enrichedHubs }
            
            for hubIndex in enrichedHubs.indices {
                guard let albums = enrichedHubs[hubIndex].metadata else { continue }
                var enrichedAlbums = albums
                
                for albumIndex in enrichedAlbums.indices {
                    enrichedAlbums[albumIndex].sonosID = "\(clientID)%3A3%3A\(enrichedAlbums[albumIndex].ratingKey ?? "")"
                    if let thumb = enrichedAlbums[albumIndex].thumb {
                        enrichedAlbums[albumIndex].thumbImageURL = getBaseURL(for: plexServer)?.appending(path: thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
                    }
                }
                
                enrichedHubs[hubIndex] = PlexAlbumHub(
                    hubKey: enrichedHubs[hubIndex].hubKey,
                    key: enrichedHubs[hubIndex].key,
                    title: enrichedHubs[hubIndex].title,
                    type: enrichedHubs[hubIndex].type,
                    hubIdentifier: enrichedHubs[hubIndex].hubIdentifier,
                    context: enrichedHubs[hubIndex].context,
                    size: enrichedHubs[hubIndex].size,
                    more: enrichedHubs[hubIndex].more,
                    style: enrichedHubs[hubIndex].style,
                    metadata: enrichedAlbums
                )
            }
            
            return enrichedHubs
        } catch {
            #if MUSICSEARCHKIT_VERBOSE_LOGGING
            print(String(decoding: data, as: UTF8.self))
            print(error)
            #endif
            return nil
        }
    }

    public func lookupArtistTopTracks(key: String, limit: Int = 10) async -> [PlexMetadata] {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken else {
            return []
        }

        guard var tracksURL = getBaseURL(for: plexServer)?.appending(path: "library/metadata/\(key)/allLeaves") else {
            return []
        }
        tracksURL.append(queryItems: [
            URLQueryItem(name: "sort", value: "viewCount:desc"),
            URLQueryItem(name: "X-Plex-Container-Start", value: "0"),
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(limit)")
        ])

        var request = URLRequest(url: tracksURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = try? await session.data(for: request) else { return [] }

        do {
            let container = try decoder.decode(PlexContainer<PlexLibraryItem>.self, from: data).mediaContainer
            return await enrichMetadata(metadata: container.metadata)
        } catch {
            #if MUSICSEARCHKIT_VERBOSE_LOGGING
            print(String(decoding: data, as: UTF8.self))
            print(error)
            #endif
            return []
        }
    }

    public func lookupArtistAlbums(key: String) async -> PlexLibraryItem? {
        guard let plexServer = await getPlexServer() else {
            return nil
        }

        guard let artistURL = getBaseURL(for: plexServer)?.appending(path: "library/metadata/\(key)/children") else { return nil }
        guard let plexContainer: PlexContainer<PlexLibraryItem> = await loadAuthorized(artistURL) else { return nil }
        let container = plexContainer.mediaContainer
        return PlexLibraryItem(
            size: container.size,
            allowSync: container.allowSync,
            art: container.art,
            grandparentRatingKey: container.grandparentRatingKey,
            grandparentThumb: container.grandparentThumb,
            grandparentTitle: container.grandparentTitle,
            identifier: container.identifier,
            key: container.key,
            librarySectionID: container.librarySectionID,
            librarySectionTitle: container.librarySectionTitle,
            librarySectionUUID: container.librarySectionUUID,
            mediaTagPrefix: container.mediaTagPrefix,
            mediaTagVersion: container.mediaTagVersion,
            nocache: container.nocache,
            parentIndex: container.parentIndex,
            parentTitle: container.parentTitle,
            parentYear: container.parentYear,
            summary: container.summary,
            thumb: container.thumb,
            title1: container.title1,
            title2: container.title2,
            viewGroup: container.viewGroup,
            metadata: await enrichMetadata(metadata: container.metadata)
        )
    }

    public func getPlexServers() async -> [PlexServer] {
        guard let token = authenticator.authToken else { return [] }
        var components = URLComponents(string: "https://plex.tv/api/v2/resources")!
        components.queryItems = [.init(name: "includeHttps", value: "1"), .init(name: "includeRelay", value: "1")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, urlResponse) = try? await session.data(for: request) else { return [] }
        
        if let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 401 {
            // MARK: Reset
            Task { @MainActor in
                authenticator.authToken = nil
                serverID = nil
            }
            return []
        }
        
        #if MUSICSEARCHKIT_VERBOSE_LOGGING
        let xml = String(decoding: data, as: UTF8.self)
        logger.info("\(xml)")
        #endif
        
        do {
            let plexServers = try decoder.decode([PlexServer].self, from: data)
            #if MUSICSEARCHKIT_VERBOSE_LOGGING
            logger.info(plexServers)
            #endif
            
            return plexServers.filter { $0.accessToken != nil }
        } catch {
            #if MUSICSEARCHKIT_VERBOSE_LOGGING
            print(String(decoding: data, as: UTF8.self))
            print(error)
            assertionFailure(String(decoding: data, as: UTF8.self))
            #endif
            return []
        }
    }

    private func getPlexServer() async -> PlexServer? {
//        let jsonData = """
// {
//        "name": "The Mothership",
//        "product": "Plex Media Server",
//        "productVersion": "1.41.0.8992-8463ad060",
//        "platform": "MacOSX",
//        "platformVersion": "15.0.0",
//        "device": "Mac14,3",
//        "clientIdentifier": "883946cf10e29d817ec3f89bf8ae36d14978176a",
//        "createdAt": "2016-09-04T19:10:07Z",
//        "lastSeenAt": "2024-09-16T22:00:39Z",
//        "provides": "server",
//        "ownerId": null,
//        "sourceTitle": null,
//        "publicAddress": "212.159.69.190",
//        "accessToken": "KSAM-R573sKNdDdk2i-G",
//        "owned": true,
//        "home": false,
//        "synced": false,
//        "relay": true,
//        "presence": true,
//        "httpsRequired": false,
//        "publicAddressMatches": false,
//        "dnsRebindingProtection": false,
//        "natLoopbackSupported": true,
//        "connections": [
//          {
//            "protocol": "https",
//            "address": "192.168.135.254",
//            "port": 32400,
//            "uri": "https://192-168-135-254.b9c7c12bf5f64e85a1a12a53f4e74f69.plex.direct:32400",
//            "local": true,
//            "relay": false,
//            "IPv6": false
//          },
//          {
//            "protocol": "https",
//            "address": "212.159.69.190",
//            "port": 50000,
//            "uri": "https://212-159-69-190.b9c7c12bf5f64e85a1a12a53f4e74f69.plex.direct:50000",
//            "local": false,
//            "relay": false,
//            "IPv6": false
//          },
//          {
//            "protocol": "https",
//            "address": "178.79.176.52",
//            "port": 8443,
//            "uri": "https://178-79-176-52.b9c7c12bf5f64e85a1a12a53f4e74f69.plex.direct:8443",
//            "local": false,
//            "relay": true,
//            "IPv6": false
//          }
//        ]
//      }
//"""
//        return try? JSONDecoder().decode(PlexServer.self, from: jsonData.data(using: .utf8)!)
        if let cached = withCacheLock({ plexServer }) {
            return cached
        }
        let plexServers = await getPlexServers()
        let preferredServer = plexServers.filter { $0.clientIdentifier == serverID }.first
        // Resolve the fastest connection once so browse requests reuse it.
        var resolved: URL?
        if let preferredServer {
            resolved = await resolveBaseURL(for: preferredServer)
        }
        withCacheLock {
            plexServer = preferredServer
            resolvedBaseURL = resolved
        }
        return preferredServer
    }

    private func getBaseURL(for plexServer: PlexServer) -> URL? {
        return withCacheLock { resolvedBaseURL } ?? plexServer.baseURL(preferring: connectionPreference)
    }

    /// Performs a request; if it fails at the connection level, re-resolves this
    /// server's connection and retries once against a *different* connection —
    /// so a cached local URL that's unreachable after leaving home transparently
    /// fails over to remote (and vice-versa). Keeps the cached server (no extra
    /// plex.tv round trip); only the stale connection is re-raced, and the retry
    /// only fires when re-resolution yields a different connection (avoids
    /// doubling the timeout when the server is simply down).
    private func loadData(for request: URLRequest) async -> (Data, URLResponse)? {
        if let result = try? await session.data(for: request) {
            return result
        }
        guard let url = request.url,
              let server = await getPlexServer() else {
            return nil
        }
        // Force a fresh race for this server's connection and cache the winner.
        let newBase = await resolveBaseURL(for: server, forceRefresh: true)
        withCacheLock { resolvedBaseURL = newBase }
        guard let newBase,
              let retryURL = url.rebasing(to: newBase),
              retryURL != url else {
            return nil
        }
        var retryRequest = request
        retryRequest.url = retryURL
        return try? await session.data(for: retryRequest)
    }

    private func authorizedRequest(from url: URL) async -> URLRequest? {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken else { 
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Clic", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")
        return request
    }

    private func loadAuthorized<T: Decodable>(_ url: URL) async -> T? {
        guard let request = await authorizedRequest(from: url) else {
            return nil
        }

        guard let (data, urlResponse) = await loadData(for: request) else { return nil }
        
        if let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 401 {
            // MARK: Reset
            Task { @MainActor in
                authenticator.authToken = nil
                serverID = nil
            }
            return nil
        }
        
        #if MUSICSEARCHKIT_VERBOSE_LOGGING
        let xml = String(decoding: data, as: UTF8.self)
        logger.info("\(xml)")
        #endif
        
        do {
            let response = try decoder.decode(T.self, from: data)
            return response
        } catch {
            #if MUSICSEARCHKIT_VERBOSE_LOGGING
            print(String(decoding: data, as: UTF8.self))
            print(error)
            assertionFailure(String(decoding: data, as: UTF8.self))
            #endif
            return nil
        }
    }

    private func enrichMetadata(metadata: [PlexMetadata]?) async -> [PlexMetadata] {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken,
                let clientID = plexServer.clientIdentifier,
                let metadata else { return [] }

        return metadata.map { item in
            var updatedItem = item
            updatedItem.sonosID = "\(clientID)%3A3%3A\(item.ratingKey)"
            if let thumb = item.thumb {
                updatedItem.thumbImageURL = getBaseURL(for: plexServer)?.appending(path: thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
            }
            
            if let art = item.art {
                updatedItem.artImageURL = getBaseURL(for: plexServer)?.appending(path: art).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
            }

            updatedItem.streamURL = streamURL(for: item, server: plexServer, token: token)

            return updatedItem
        }
    }

    /// Builds a token-authenticated URL to stream a track's media file from the
    /// server. Returns nil for items without a playable part (e.g. albums,
    /// artists, playlists), so only tracks get a stream URL.
    private func streamURL(for item: PlexMetadata, server: PlexServer, token: String) -> URL? {
        guard let partKey = item.media?.first?.part.first?.key else { return nil }
        return getBaseURL(for: server)?
            .appending(path: partKey)
            .appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
    }
}

private extension URL {
    /// Returns a copy of this URL with its scheme/host/port replaced by those
    /// of `base`, preserving the path and query. Used to retry a Plex request
    /// against a different connection of the same server.
    func rebasing(to base: URL) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let baseComponents = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = baseComponents.scheme
        components.host = baseComponents.host
        components.port = baseComponents.port
        return components.url
    }
}
