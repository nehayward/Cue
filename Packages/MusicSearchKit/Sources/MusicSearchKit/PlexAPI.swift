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
            UserDefaults.standard.set(serverID, forKey: "com.cue.plexServer")
        }
    }
    
    public var librarySelectionID: String? {
        didSet {
            UserDefaults.standard.set(librarySelectionID, forKey: "com.cue.plexServer.library")
        }
    }

    @ObservationIgnored
    public var connectionPreference: ConnectionPreference {
        get {
            access(keyPath: \.connectionPreference)
            if let preference = UserDefaults.standard.string(forKey: "com.cue.plexServer.connectionPreference"), let connection = ConnectionPreference(rawValue: preference) {
                return connection
            }
            return ConnectionPreference.auto
        }
        set {
            withMutation(keyPath: \.connectionPreference) {
                UserDefaults.standard.set(newValue.rawValue, forKey: "com.cue.plexServer.connectionPreference")
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
        
        self.librarySelectionID = UserDefaults.standard.string(forKey: "com.cue.plexServer.library")
        self.serverID = UserDefaults.standard.string(forKey: "com.cue.plexServer")
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    /// What a timeline report says the player is doing.
    public enum TimelineState: String, Sendable {
        case playing
        case paused
        case stopped
    }

    /// Reports where this device is in a track, the way Plex's own players
    /// do: the server shows it under Now Playing while it is `playing` or
    /// `paused`, and counts the play — play count, Recently Played, last
    /// played — once a report puts it past the server's played threshold.
    /// Send one every few seconds while playing, on every pause, and a
    /// `stopped` when the track is left, wherever it got to.
    @discardableResult
    public func reportTimeline(ratingKey: String, state: TimelineState, time: TimeInterval, duration: TimeInterval) async -> Bool {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken,
              var timelineURL = getBaseURL(for: plexServer)?.appending(path: ":/timeline") else {
            return false
        }
        timelineURL.append(queryItems: [
            URLQueryItem(name: "ratingKey", value: ratingKey),
            URLQueryItem(name: "key", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "state", value: state.rawValue),
            URLQueryItem(name: "time", value: "\(Int(max(0, time) * 1000))"),
            URLQueryItem(name: "duration", value: "\(Int(max(0, duration) * 1000))")
        ])
        var request = URLRequest(url: timelineURL)
        request.timeoutInterval = 10
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Product")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")
        guard let (_, response) = await loadData(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    // MARK: - Lyrics

    /// The track's lyrics from the server: its lyric streams (a sidecar
    /// `.lrc` or `.txt` beside the file, or the lyrics agent's, which needs
    /// Plex Pass), timed ones first. An agent's stream answers in JSON,
    /// line by line; a sidecar's with the file itself.
    ///
    /// `nil` when the server answered and the track has none; throws when
    /// the server couldn't be asked, or listed lyrics it couldn't serve, so
    /// a passing fault isn't taken for "no lyrics".
    public func lyrics(ratingKey: String) async throws -> Lyrics? {
        let log = LyricsLookupError.log
        guard let plexServer = await getPlexServer(), let baseURL = getBaseURL(for: plexServer) else {
            log.info("plex \(ratingKey, privacy: .public): no server")
            throw LyricsLookupError("no Plex server")
        }
        guard let request = await authorizedRequest(from: baseURL.appending(path: "library/metadata/\(ratingKey)")),
              let (data, response) = await loadData(for: request) else {
            log.info("plex \(ratingKey, privacy: .public): metadata unreachable")
            throw LyricsLookupError("Plex unreachable")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard status == 200 else {
            log.info("plex \(ratingKey, privacy: .public): metadata answered \(status, privacy: .public)")
            if status == 404 { return nil }
            throw LyricsLookupError("Plex answered \(status)")
        }
        guard let container = try? decoder.decode(PlexLyricStreamsContainer.self, from: data) else {
            log.info("plex \(ratingKey, privacy: .public): metadata didn't decode")
            return nil
        }
        let streams = container.lyricStreams
        log.info("plex \(ratingKey, privacy: .public): \(streams.count, privacy: .public) lyric streams \(streams.map { "\($0.format ?? $0.codec ?? "?")\($0.timed ? " timed" : "") \($0.provider ?? "")" }.joined(separator: ", "), privacy: .public)")
        let ordered = streams.filter(\.isLikelyTimed) + streams.filter { !$0.isLikelyTimed }
        // An agent's lyrics come from LyricFind, through Plex, which limits
        // how often a server may ask: a check of 150 songs, a few requests
        // each, shut it off after five. So one request a song — the timed
        // stream if there is one, asked for the one way that works — and
        // none while it rests after refusals, since asking then only keeps
        // it shut. A sidecar is a file on the server, free to ask for.
        let hasAgent = streams.contains(where: \.isAgent)
        let pausedUntil = hasAgent ? Self.lyricFindCooldown.pausedUntil() : nil
        if let pausedUntil {
            log.info("plex \(ratingKey, privacy: .public): LyricFind paused until \(pausedUntil.formatted(date: .omitted, time: .shortened), privacy: .public)")
        }
        let agent = pausedUntil == nil ? ordered.first { $0.isAgent && $0.key != nil } : nil
        var unreachable = false
        for stream in ordered where !stream.isAgent || stream.key == agent?.key {
            guard let key = stream.key else { continue }
            let url = baseURL.appending(path: key.trimmingPrefix("/"))
            // Plex's own apps ask for a stream rendered (`format=xml`): an
            // agent's lyrics (LyricFind) aren't a file on the server, which
            // fetches them when asked, and a bare request for one is a 404.
            // A sidecar's stream answers either way.
            let rendered = url.appending(queryItems: [
                URLQueryItem(name: "format", value: "xml"),
                URLQueryItem(name: "includeInlineAttribution", value: "1")
            ])
            let attempts = stream.isAgent ? [rendered] : [rendered, url]
            for attempt in attempts {
                guard let request = await authorizedRequest(from: attempt),
                      let (body, response) = await loadData(for: request) else {
                    unreachable = true
                    continue
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                let preview = String(decoding: body.prefix(60), as: UTF8.self).replacingOccurrences(of: "\n", with: " ")
                log.info("plex \(ratingKey, privacy: .public): \(key, privacy: .public)\(attempt.query.map { "?" + $0 } ?? "", privacy: .public) answered \(status, privacy: .public): \(preview, privacy: .public)")
                guard status == 200 else {
                    if stream.isAgent, status == 404 {
                        let pause = Self.lyricFindCooldown.refused()
                        if pause > 0 {
                            log.info("plex: LyricFind refused three songs running; not asked again for \(Int(pause / 60), privacy: .public) min")
                        }
                    }
                    continue
                }
                if let lyrics = PlexLyricsContainer.lyrics(fromStream: body, credit: stream.credit) {
                    if stream.isAgent { Self.lyricFindCooldown.served() }
                    return lyrics
                }
            }
        }
        if unreachable { throw LyricsLookupError("Plex unreachable") }
        if pausedUntil != nil { throw LyricsLookupError("LyricFind paused") }
        // Listed but none would load: the server couldn't fetch them (an
        // agent's lyrics come from LyricFind when asked, which fails at
        // times), not a song without lyrics.
        if !streams.isEmpty { throw LyricsLookupError("Plex lyric streams didn't load") }
        return nil
    }

    /// Plex answers a 404 for a LyricFind stream it listed both now and
    /// then for one song (served a minute later for others, and later for
    /// it) and, once a server has asked too much, for every song for a
    /// long while. Asking while shut out only keeps it shut, so three
    /// refusals running count as that: LyricFind isn't asked for 15
    /// minutes, doubling each time to 6 hours. Lyrics it serves reset it.
    static let lyricFindCooldown = LyricFindCooldown()

    final class LyricFindCooldown: Sendable {
        private struct State {
            var pausedUntil: Date = .distantPast
            var pause: TimeInterval = LyricFindCooldown.shortest
            var refusalsInARow = 0
        }

        static let shortest: TimeInterval = 15 * 60
        static let longest: TimeInterval = 6 * 60 * 60
        /// Refusals running that mean the server is shut out, not the song.
        static let refusalsBeforePause = 3

        private let state = OSAllocatedUnfairLock(initialState: State())

        /// When LyricFind may be asked again, or nil if it may now.
        func pausedUntil(at now: Date = .now) -> Date? {
            state.withLock { $0.pausedUntil > now ? $0.pausedUntil : nil }
        }

        /// Records a refusal; returns how long LyricFind now rests, 0 while
        /// it's still taken as the song's.
        @discardableResult
        func refused(at now: Date = .now) -> TimeInterval {
            state.withLock { state in
                state.refusalsInARow += 1
                guard state.refusalsInARow >= Self.refusalsBeforePause else { return 0 }
                state.refusalsInARow = 0
                let pause = state.pause
                state.pausedUntil = now.addingTimeInterval(pause)
                state.pause = min(pause * 2, Self.longest)
                return pause
            }
        }

        func served() {
            state.withLock { $0 = State() }
        }
    }

    /// The track's lyric streams as Plex lists them — format, whether
    /// timed, provider — for checking the lyrics a library has; `nil` when
    /// the server couldn't be asked.
    public func lyricStreamDescriptions(ratingKey: String) async -> [String]? {
        guard let plexServer = await getPlexServer(),
              let baseURL = getBaseURL(for: plexServer),
              let request = await authorizedRequest(from: baseURL.appending(path: "library/metadata/\(ratingKey)")),
              let (data, response) = await loadData(for: request),
              (response as? HTTPURLResponse)?.statusCode ?? 200 == 200,
              let container = try? decoder.decode(PlexLyricStreamsContainer.self, from: data) else { return nil }
        return container.lyricStreams.map { stream in
            [stream.format ?? stream.codec ?? "?", stream.timed ? "timed" : nil, stream.credit ?? stream.provider.map { $0.replacingOccurrences(of: "com.plexapp.agents.", with: "") }]
                .compactMap { $0 }
                .joined(separator: " ")
        }
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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

    /// Batch metadata lookup, keyed by ratingKey — one request for any mix of
    /// tracks and albums. Some servers omit detail from `/hubs/search`
    /// responses (a track's `Media` element with codec/bitrate, an album's
    /// `leafCount`), so search results are enriched from
    /// `/library/metadata/{id,id,...}`, which always includes it.
    public func batchMetadata(ratingKeys: [String]) async -> [String: PlexMetadata] {
        guard !ratingKeys.isEmpty,
              let plexServer = await getPlexServer(),
              let token = plexServer.accessToken,
              let url = getBaseURL(for: plexServer)?.appending(path: "library/metadata/\(ratingKeys.joined(separator: ","))") else {
            return [:]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = await loadData(for: request),
              let container = try? decoder.decode(PlexContainer<PlexBatchMetadata>.self, from: data).mediaContainer else {
            return [:]
        }

        var metadataByKey: [String: PlexMetadata] = [:]
        for item in container.metadata ?? [] {
            metadataByKey[item.ratingKey] = item
        }
        return metadataByKey
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

    /// The server's audio playlists, all in one response. With a `sort`,
    /// Plex returns them in that order (`reversed` flips its natural
    /// direction); without one, in its own.
    public func playlists(sort: PlexPlaylistSort? = nil, reversed: Bool = false) async -> [PlexUserPlaylist] {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken else {
            return []
        }
        
        #if MUSICSEARCHKIT_VERBOSE_LOGGING
        logger.info(plexServer)
        #endif

        guard var playlistsURL = getBaseURL(for: plexServer)?.appending(path: "playlists") else { return [] }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "playlistType", value: "audio")
        ]
        if let sort {
            queryItems.append(URLQueryItem(name: "sort", value: sort.queryValue(reversed: reversed)))
        }
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

    
    /// A page of the library's albums in the requested order. Plex sorts on
    /// the server, so the order (reversed included) holds across every page.
    public func albums(
        sort: PlexAlbumSort = .title,
        reversed: Bool = false,
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
            URLQueryItem(name: "sort", value: sort.queryValue(reversed: reversed)),
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
        sort: PlexSongSort = .title,
        reversed: Bool = false,
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
            URLQueryItem(name: "sort", value: sort.queryValue(reversed: reversed)),
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(limit)"),
            URLQueryItem(name: "X-Plex-Container-Start", value: "\(offset)")
        ]
        albumURL.append(queryItems: queryItems)

        guard let songContainer: PlexContainer<PlexSongItem> = await loadAuthorized(albumURL) else {
            return []
        }

        guard let songs = songContainer.mediaContainer.metadata else { return [] }
        return decorated(songs, server: plexServer, token: token)
    }

    /// A page of songs together with the section's total, for a sync that
    /// wants to know how far it has to go.
    public func songPage(offset: Int, limit: Int) async -> (songs: [PlexMetadata], total: Int?) {
        guard let plexServer = await getPlexServer(),
              let token = plexServer.accessToken else { return ([], nil) }

        if librarySelectionID == nil {
            librarySelectionID = await getMusicLibrarySection()
        }

        guard let sectionKey = librarySelectionID,
              var url = getBaseURL(for: plexServer)?.appending(path: "/library/sections/\(sectionKey)/all")
        else { return ([], nil) }

        url.append(queryItems: [
            URLQueryItem(name: "type", value: "10"),
            URLQueryItem(name: "X-Plex-Container-Size", value: "\(limit)"),
            URLQueryItem(name: "X-Plex-Container-Start", value: "\(offset)")
        ])

        guard let container: PlexContainer<PlexSongItem> = await loadAuthorized(url) else { return ([], nil) }
        let songs = container.mediaContainer.metadata ?? []
        return (decorated(songs, server: plexServer, token: token), container.mediaContainer.totalSize)
    }

    /// Fills in the fields Plex doesn't send: the Sonos id and the
    /// token-carrying stream and artwork URLs. Kept out of the model — and so
    /// out of anything saved to disk — because the token rotates, and a
    /// cached URL carrying an old one would simply fail.
    public func decorated(_ songs: [PlexMetadata], server: PlexServer, token: String) -> [PlexMetadata] {
        guard let id = server.clientIdentifier else { return songs }

        var songs = songs
        for index in songs.indices {
            songs[index].sonosID = "\(id)%3A3%3A\(songs[index].ratingKey)"
            songs[index].streamURL = streamURL(for: songs[index], server: server, token: token)
            guard let thumb = songs[index].thumb else { continue }
            songs[index].thumbImageURL = getBaseURL(for: server)?
                .appending(path: thumb)
                .appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
        }
        return songs
    }

    /// The same, resolving the server itself — for songs restored from the
    /// cache, which were saved without their token-carrying URLs.
    public func decorated(_ songs: [PlexMetadata]) async -> [PlexMetadata] {
        guard let server = await getPlexServer(), let token = server.accessToken else { return songs }
        return decorated(songs, server: server, token: token)
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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
                    request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            let mediaContainer = try decoder.decode(PlexContainer<PlexSongItem>.self, from: data).mediaContainer
            return PlexSongItem(
                size: mediaContainer.size,
                totalSize: mediaContainer.totalSize,
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
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

    /// The URL this device streams a track from, honoring the user's
    /// transcoding choice: the direct file URL (`streamURL`, as carried in
    /// `previewURL`) when nothing is transcoded, otherwise the server's
    /// universal transcoder asked for the same track as MP3 or Opus at the
    /// chosen bitrate (`protocol=http`, the shape Plexamp's "convert" modes
    /// use). Built from the direct URL so it needs no server lookup: the
    /// scheme, host, port and token are taken from it, and `ratingKey` names
    /// the track (`path=/library/metadata/<ratingKey>`). Each track gets its
    /// own transcode `session`, so a song fetched ahead doesn't cancel the
    /// one playing.
    ///
    /// The server only transcodes to a target its client profile lists, and
    /// the built-in profiles carry MP3 over HTTP but not Opus — asking for
    /// Opus on one gets a 400 page. So the request declares its own target
    /// (`X-Plex-Client-Profile-Extra`, the way Plexamp does) on the generic
    /// profile, in Plex's container names (Ogg for Opus).
    ///
    /// Speaker playback isn't affected: Plex hands Sonos its own stream via
    /// the Plex music service, whose quality is set on the Plex server.
    public static func playbackStreamURL(from directURL: URL, ratingKey: String) -> URL {
        playbackStreamURL(from: directURL, ratingKey: ratingKey, format: StreamTranscoding.format(for: .device), bitrate: StreamTranscoding.bitrate)
    }

    /// The same, transcoded to `format` at `bitrate` whatever the Streaming
    /// Quality setting says — for a device with a quality of its own (the
    /// Apple Watch). Its transcode session and client are named apart
    /// (`session`, `client`), so Plex doesn't take it for this iPhone's and
    /// end one for the other.
    public static func playbackStreamURL(from directURL: URL, ratingKey: String, format: StreamTranscoding.Format, bitrate: Int, session: String = "cue", client: String = "Cue") -> URL {
        guard let codec = format.codec,
              let container = plexContainer(for: format),
              var components = URLComponents(url: directURL, resolvingAgainstBaseURL: false),
              !ratingKey.isEmpty
        else { return directURL }
        let token = components.queryItems?.first { $0.name == "X-Plex-Token" }?.value
        let target = "add-transcode-target(type=musicProfile&context=streaming&protocol=http&container=\(container)&audioCodec=\(codec))"
        components.path = "/music/:/transcode/universal/start.\(container)"
        components.queryItems = [
            URLQueryItem(name: "path", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "mediaIndex", value: "0"),
            URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "protocol", value: "http"),
            URLQueryItem(name: "directPlay", value: "0"),
            URLQueryItem(name: "directStream", value: "0"),
            URLQueryItem(name: "audioCodec", value: codec),
            URLQueryItem(name: "musicBitrate", value: "\(bitrate)"),
            URLQueryItem(name: "session", value: "\(session)-\(ratingKey)"),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: client),
            URLQueryItem(name: "X-Plex-Product", value: "Cue"),
            URLQueryItem(name: "X-Plex-Platform", value: "Generic"),
            URLQueryItem(name: "X-Plex-Client-Profile-Extra", value: target)
        ] + (token.map { [URLQueryItem(name: "X-Plex-Token", value: $0)] } ?? [])
        return components.url ?? directURL
    }

    /// Plex's container name for a transcode format: Opus travels in Ogg.
    private static func plexContainer(for format: StreamTranscoding.Format) -> String? {
        switch format {
        case .original: nil
        case .mp3: "mp3"
        case .opus: "ogg"
        }
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
