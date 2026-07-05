import Foundation
import OSLog

// Empty response type for PUT/DELETE operations that don't return content
private struct EmptyResponse: Codable {}

// Returned by playlist mutation endpoints (add/remove tracks)
private struct SpotifySnapshotResponse: Codable {
    let snapshotId: String
}

// Created when POSTing a new playlist
private struct SpotifyCreatePlaylistResponse: Codable {
    let id: String
}

// Minimal `/playlists/{id}?fields=collaborative,owner.id` response for the editability check.
private struct SpotifyPlaylistEditability: Decodable {
    struct Owner: Decodable { let id: String }
    let collaborative: Bool
    let owner: Owner
}

/**
 * SpotifyAPI provides access to Spotify's Web API with support for token refresh handling.
 * 
 * The API requires a TokenRefreshHandler to function. When initialized with a TokenRefreshHandler, the API will:
 * - Use credentials from the handler for authentication on each request
 * - Automatically retry requests when receiving 401 responses
 * - Allow external token refresh responses to be processed
 * 
 * Example usage:
 * ```swift
 * let tokenHandler = KeychainTokenRefreshHandler.shared
 * let spotifyAPI = SpotifyAPI(tokenRefreshHandler: tokenHandler)
 * 
 * // Search for tracks
 * let results = await spotifyAPI.search(for: "query", types: [.track])
 * 
 * // Handle external token refresh (e.g., from Sonos)
 * try await spotifyAPI.handleTokenRefreshResponse(
 *     householdId: "household_id", 
 *     refreshResponse: tokenRefreshResponse
 * )
 * ```
 * 
 * Note: The API will throw AuthError.missingTokenHandler if no token refresh handler is provided.
 */
public final class SpotifyAPI {
    private let logger: Logger = Logger(subsystem: "SpotifySearchAPI", category: "SpotifySearchAPI")
    private let session: URLSession
    private let decoder: JSONDecoder
    private let tokenRefreshHandler: TokenRefreshHandler?
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 0.5 // 500 milliseconds

    /// Spotify only sends the slim, market-aware payload when a market is specified: the
    /// deprecated `available_markets` array (~185 country codes on every track and album
    /// object) is replaced by a single `is_playable` flag. `from_token` resolves to the
    /// country on the user's access token, so availability is unchanged — responses are
    /// just much smaller and faster to download and decode.
    private static let marketFilter = URLQueryItem(name: "market", value: "from_token")

    public init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder(), tokenRefreshHandler: TokenRefreshHandler? = nil) {
        self.tokenRefreshHandler = tokenRefreshHandler
        self.session = session
        self.decoder = decoder
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
    }

    public func lookupUser(for userID: String) async -> SpotifyUser? {
        guard let userID = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/users/\(userID)"

        guard let url = components.url else { return nil }

        do {
            let user: SpotifyUser = try await authorizedRequest(url)
            return user
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }

    public func search(for query: String, limit: Int = 30, types: Set<SpotifyType>) async -> SpotifyResult? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: types.map(\.rawValue).joined(separator: ",")),
            URLQueryItem(name: "limit", value: "\(limit)"),
            Self.marketFilter
        ]

        guard let url = components.url else { return nil }

        do {
            let spotifySearch: SpotifyResult = try await authorizedRequest(url)
            return spotifySearch
        } catch {
//            logger.error("\(error.localizedDescription)")
            return nil
        }
    }

    public func searchSong(for query: String, limit: Int = 25) async -> SpotifyResult? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            Self.marketFilter
        ]

        guard let url = components.url else { return nil }

        do {
            let spotifySearch: SpotifyResult = try await authorizedRequest(url)
            return spotifySearch
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }

    /// Full album objects (with popularity and per-track explicit flags) for
    /// the given ids. Search returns simplified albums without popularity, so
    /// results are enriched via this batch lookup. Chunks by Spotify's
    /// 20-ids-per-request cap; failed chunks are skipped.
    public func albums(ids: [String]) async -> [SpotifyAlbumDetails] {
        var albums: [SpotifyAlbumDetails] = []
        for chunk in stride(from: 0, to: ids.count, by: 20).map({ Array(ids[$0..<min($0 + 20, ids.count)]) }) {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "api.spotify.com"
            components.path = "/v1/albums"
            components.queryItems = [
                URLQueryItem(name: "ids", value: chunk.joined(separator: ",")),
                Self.marketFilter
            ]

            guard let url = components.url else { continue }

            do {
                let batch: SpotifyAlbumsBatch = try await authorizedRequest(url)
                albums.append(contentsOf: batch.albums.compactMap { $0 })
            } catch {
                logger.error("\(error.localizedDescription)")
            }
        }
        return albums
    }

    public func newReleases() async -> SpotifyResult? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/browse/new-releases"
     
        guard let url = components.url else { return nil }

        do {
            let spotifySearch: SpotifyResult = try await authorizedRequest(url)
            return spotifySearch
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }

    public func lookupTrack(id: String) async -> SpotifyTrackItem? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/tracks/\(id)"
        components.queryItems = [Self.marketFilter]
        guard let url = components.url else { return nil }

        do {
            let spotifyTrack: SpotifyTrackItem = try await authorizedRequest(url)
            return spotifyTrack
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }

    public func save(id: String) async -> SpotifyTrackItem? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/tracks/\(id)"
        components.queryItems = [Self.marketFilter]
        guard let url = components.url else { return nil }

        do {
            let spotifyTrack: SpotifyTrackItem = try await authorizedRequest(url)
            return spotifyTrack
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }

    public func removeTrack(id: String) async -> SpotifyTrackItem? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/tracks/\(id)"
        components.queryItems = [Self.marketFilter]
        guard let url = components.url else { return nil }

        do {
            let spotifyTrack: SpotifyTrackItem = try await authorizedRequest(url)
            return spotifyTrack
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }

    public func playlist(id: String) async -> SpotifyPlaylistItems? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/playlists/\(id)"
        // Callers only use the playlist metadata (name, owner, images, track count), so
        // filter out `tracks.items` — otherwise Spotify inlines the first 100 full track
        // objects, which dwarfs the rest of the response. `PlaylistTracks.items` is
        // optional, so decoding is unaffected; use `playlistTracks(id:)` for the tracks.
        components.queryItems = [
            URLQueryItem(name: "fields", value: "collaborative,description,external_urls,href,id,images,name,owner(display_name,external_urls,href,id,type,uri),public,snapshot_id,tracks(href,total),type,uri"),
            Self.marketFilter
        ]

        guard let url = components.url else { return nil }

        do {
            let spotifyPlaylist: SpotifyPlaylistItems = try await authorizedRequest(url)
            return spotifyPlaylist
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }
    
    public func userPlaylists(userID: String) async -> SpotifyUserPlaylistsResponse? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/users/\(userID)/playlists"
        guard let url = components.url else { return nil }

        do {
            let spotifyPlaylist: SpotifyUserPlaylistsResponse = try await authorizedRequest(url)
            return spotifyPlaylist
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }
    
    public func playlistTracks(id: String, offset: Int = 0, limit: Int = 50) async -> (SpotifyPlaylistsFullContainer?) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/playlists/\(id)/tracks"
        // `SpotifyPlaylistsFullContainer` only decodes `total` and each item's `uid` and
        // `track`, so ask for exactly that — dropping added_at/added_by/video_thumbnail
        // and the paging boilerplate from every one of the 50 items per page.
        components.queryItems = [
            .init(name: "offset", value: "\(offset)"),
            .init(name: "limit", value: "\(limit)"),
            .init(name: "fields", value: "total,items(uid,track)"),
            Self.marketFilter
        ]
        guard let url = components.url else { return nil }

        do {
            let spotifyPlaylist: SpotifyPlaylistsFullContainer = try await authorizedRequest(url)
            return spotifyPlaylist
        } catch {
            print(error.localizedDescription)
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }
    
    public func userPlaylists(offset: Int = 0, limit: Int = 50) async -> SpotifyUserPlaylistsResponse? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/me/playlists"
        components.queryItems = [
            .init(name: "offset", value: "\(offset)"),
            .init(name: "limit", value: "\(limit)")
        ]
        guard let url = components.url else { return nil }

        do {
            let playlists: SpotifyUserPlaylistsResponse = try await authorizedRequest(url)
            return playlists
        } catch {
            print(error.localizedDescription)
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }
    
    public func userTracks(offset: Int = 0, limit: Int = 50) async -> SpotifyUserTracksResponse? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/me/tracks"
        components.queryItems = [
            .init(name: "offset", value: "\(offset)"),
            .init(name: "limit", value: "\(limit)"),
            Self.marketFilter
        ]
        guard let url = components.url else { return nil }

        do {
            let songs: SpotifyUserTracksResponse = try await authorizedRequest(url)
            return songs
        } catch {
            print(error.localizedDescription)
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }
    
    public func userAlbums(offset: Int = 0, limit: Int = 50) async -> SpotifyUserAlbumResponse? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/me/albums"
        components.queryItems = [
            .init(name: "offset", value: "\(offset)"),
            .init(name: "limit", value: "\(limit)"),
            Self.marketFilter
        ]
        guard let url = components.url else { return nil }

        do {
            let userAlbums: SpotifyUserAlbumResponse = try await authorizedRequest(url)
            return userAlbums
        } catch {
            print(error.localizedDescription)
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }
    
    public func album(id: String) async -> SpotifyAlbumItem? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/albums/\(id)"
        components.queryItems = [Self.marketFilter]
        guard let url = components.url else { return nil }

        do {
            let album: SpotifyAlbumItem = try await authorizedRequest(url)
            return album
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }

    public func albumDetails(id: String, offset: Int = 0, limit: Int = 50) async -> SpotifyAlbumDetails? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/albums/\(id)"
        components.queryItems = [
            .init(name: "offset", value: "\(offset)"),
            .init(name: "limit", value: "\(limit)"),
            Self.marketFilter
        ]

        guard let url = components.url else { return nil }

        do {
            let spotifyAlbum: SpotifyAlbumDetails = try await authorizedRequest(url)
            return spotifyAlbum
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }

    public func artist(id: String) async -> SpotifyArtistsItems? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/artists/\(id)"
        components.queryItems = [
//            URLQueryItem(name: "market", value: ""),
        ]
        guard let url = components.url else { return nil }

        do {
            let artist: SpotifyArtistsItems = try await authorizedRequest(url)
            return artist
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }

    public func artistTopTracks(id: String) async -> [SpotifyTrackItem] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/artists/\(id)/top-tracks"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "50"),
            Self.marketFilter
        ]

        guard let url = components.url else { return [] }
//
        do {
            let spotifyArtistTopTracks: SpotifyArtistTopTracks = try await authorizedRequest(url)
            return spotifyArtistTopTracks.tracks
        } catch {
            logger.error("\(error.localizedDescription)")
            return []
        }
    }

    public func artistAlbums(id: String) async -> SpotifyArtistAlbums? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/artists/\(id)/albums"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "include_groups", value: "album"),
            Self.marketFilter
        ]

        guard let url = components.url else { return nil }

        do {
            let tracks: SpotifyArtistAlbums = try await authorizedRequest(url)
            return tracks
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }

    public func saveTrack(id: String) async -> Bool {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/me/tracks"
        components.queryItems = [
            URLQueryItem(name: "ids", value: id)
        ]
        guard let url = components.url else { return false }

        do {
            let _: EmptyResponse = try await authorizedRequest(url, method: "PUT")
            return true
        } catch {
            logger.error("Failed to save track: \(error.localizedDescription)")
            return false
        }
    }
    
    public func deleteTrack(id: String) async -> Bool {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/me/tracks"
        components.queryItems = [
            URLQueryItem(name: "ids", value: id)
        ]
        guard let url = components.url else { return false }

        do {
            let _: EmptyResponse = try await authorizedRequest(url, method: "DELETE")
            return true
        } catch {
            logger.error("Failed to delete track: \(error.localizedDescription)")
            return false
        }
    }
    
    public func isTrackSaved(id: String) async -> Bool {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/me/tracks/contains"
        components.queryItems = [
            URLQueryItem(name: "ids", value: id)
        ]
        guard let url = components.url else { return false }

        do {
            let savedStatus: [Bool] = try await authorizedRequest(url)
            return savedStatus.first ?? false
        } catch {
            logger.error("Failed to check if track is saved: \(error.localizedDescription)")
            return false
        }
    }

    public func saveAlbum(id: String) async -> Bool {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/me/albums"
        components.queryItems = [URLQueryItem(name: "ids", value: id)]
        guard let url = components.url else { return false }
        do {
            let _: EmptyResponse = try await authorizedRequest(url, method: "PUT")
            return true
        } catch {
            logger.error("Failed to save album: \(error.localizedDescription)")
            return false
        }
    }

    public func deleteAlbum(id: String) async -> Bool {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/me/albums"
        components.queryItems = [URLQueryItem(name: "ids", value: id)]
        guard let url = components.url else { return false }
        do {
            let _: EmptyResponse = try await authorizedRequest(url, method: "DELETE")
            return true
        } catch {
            logger.error("Failed to delete album: \(error.localizedDescription)")
            return false
        }
    }

    public func isAlbumSaved(id: String) async -> Bool {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/me/albums/contains"
        components.queryItems = [URLQueryItem(name: "ids", value: id)]
        guard let url = components.url else { return false }
        do {
            let savedStatus: [Bool] = try await authorizedRequest(url)
            return savedStatus.first ?? false
        } catch {
            logger.error("Failed to check if album is saved: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Playlist Management

    /// The authenticated user (`/v1/me`). Needed to create playlists and to determine playlist ownership.
    public func currentUser() async -> SpotifyUser? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/me"
        guard let url = components.url else { return nil }

        do {
            let user: SpotifyUser = try await authorizedRequest(url)
            return user
        } catch {
            logger.error("Failed to fetch current user: \(error.localizedDescription)")
            return nil
        }
    }

    /// Whether the playlist is editable by `currentUserID` — they own it or it's collaborative.
    /// Uses a `fields`-filtered `/playlists/{id}` request so the response is just the owner id and
    /// collaborative flag (no tracks payload).
    public func isPlaylistEditable(id: String, currentUserID: String) async -> Bool {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/playlists/\(id)"
        components.queryItems = [URLQueryItem(name: "fields", value: "collaborative,owner.id")]
        guard let url = components.url else { return false }
        do {
            let details: SpotifyPlaylistEditability = try await authorizedRequest(url)
            return details.collaborative || details.owner.id == currentUserID
        } catch {
            logger.error("Failed to check playlist editability: \(error.localizedDescription)")
            return false
        }
    }

    /// The authenticated user's playlists that they can modify (owned or collaborative).
    public func editableUserPlaylists() async -> [SpotifyUserPlaylists] {
        guard let me = await currentUser() else { return [] }

        var results: [SpotifyUserPlaylists] = []
        var offset = 0
        let limit = 50
        // Page through the user's playlists, keeping only the editable ones.
        while true {
            guard let response = await userPlaylists(offset: offset, limit: limit) else { break }
            let page = response.items.compactMap { $0 }
            results.append(contentsOf: page.filter { $0.isEditable(by: me.id) })
            if response.next == nil || page.isEmpty { break }
            offset += limit
        }
        return results
    }

    /// Creates a new playlist owned by the authenticated user.
    public func createPlaylist(name: String, description: String? = nil, isPublic: Bool = false) async -> String? {
        guard let me = await currentUser() else { return nil }
        guard let userID = me.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/users/\(userID)/playlists"
        guard let url = components.url else { return nil }

        var attributes: [String: Any] = ["name": name, "public": isPublic]
        if let description { attributes["description"] = description }
        guard let body = try? JSONSerialization.data(withJSONObject: attributes) else { return nil }

        do {
            let response: SpotifyCreatePlaylistResponse = try await authorizedRequest(url, method: "POST", body: body)
            return response.id
        } catch {
            logger.error("Failed to create playlist: \(error.localizedDescription)")
            return nil
        }
    }

    /// Reorders items in a playlist. `rangeStart` is the index of the first item to move,
    /// `insertBefore` is the index to move it before, `rangeLength` how many contiguous items.
    public func reorderPlaylistItems(playlistID: String, rangeStart: Int, insertBefore: Int, rangeLength: Int = 1) async -> Bool {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/playlists/\(playlistID)/tracks"
        guard let url = components.url else { return false }

        let body: [String: Any] = ["range_start": rangeStart, "insert_before": insertBefore, "range_length": rangeLength]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return false }

        do {
            let _: SpotifySnapshotResponse = try await authorizedRequest(url, method: "PUT", body: data)
            return true
        } catch {
            logger.error("Failed to reorder playlist: \(error.localizedDescription)")
            return false
        }
    }

    /// Adds tracks (Spotify URIs, e.g. `spotify:track:ID`) to a playlist.
    public func addTracksToPlaylist(playlistID: String, trackURIs: [String]) async -> Bool {
        guard !trackURIs.isEmpty else { return true }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/playlists/\(playlistID)/tracks"
        guard let url = components.url else { return false }

        guard let body = try? JSONSerialization.data(withJSONObject: ["uris": trackURIs]) else { return false }

        do {
            let _: SpotifySnapshotResponse = try await authorizedRequest(url, method: "POST", body: body)
            return true
        } catch {
            logger.error("Failed to add tracks to playlist: \(error.localizedDescription)")
            return false
        }
    }

    /// Removes the given tracks (Spotify URIs) from a playlist.
    ///
    /// When `positions` is supplied it must line up 1:1 with `trackURIs`, and each track is removed
    /// only at that playlist position — so a playlist containing the same track more than once loses
    /// just the chosen occurrence. With `positions` nil, Spotify removes *all* occurrences of each URI.
    public func removeTracksFromPlaylist(playlistID: String, trackURIs: [String], positions: [Int]? = nil) async -> Bool {
        guard !trackURIs.isEmpty else { return true }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/playlists/\(playlistID)/tracks"
        guard let url = components.url else { return false }

        let tracks: [[String: Any]]
        if let positions, positions.count == trackURIs.count {
            tracks = zip(trackURIs, positions).map { ["uri": $0, "positions": [$1]] }
        } else {
            tracks = trackURIs.map { ["uri": $0] }
        }
        guard let body = try? JSONSerialization.data(withJSONObject: ["tracks": tracks]) else { return false }

        do {
            let _: SpotifySnapshotResponse = try await authorizedRequest(url, method: "DELETE", body: body)
            return true
        } catch {
            logger.error("Failed to remove tracks from playlist: \(error.localizedDescription)")
            return false
        }
    }

    /// Removes a playlist from the user's library. Spotify has no hard delete; unfollowing is the equivalent.
    public func unfollowPlaylist(playlistID: String) async -> Bool {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/playlists/\(playlistID)/followers"
        guard let url = components.url else { return false }

        do {
            let _: EmptyResponse = try await authorizedRequest(url, method: "DELETE")
            return true
        } catch {
            logger.error("Failed to unfollow playlist: \(error.localizedDescription)")
            return false
        }
    }

    enum AuthError: Error {
        case missingToken
        case invalidToken
        case tokenRefreshFailed
        case missingTokenHandler
    }

    func authorizedRequest<T: Decodable>(_ url: URL, method: String = "GET", body: Data? = nil, allowRetry: Bool = true) async throws -> T {
        guard let handler = tokenRefreshHandler else {
            throw AuthError.missingTokenHandler
        }

        var retryCount = 0
        while retryCount < maxRetries {
            if let credentials = try await handler.getCredentials() {
                var request = try await authorizedRequest(from: url, token: credentials.token)
                request.httpMethod = method
                if let body {
                    request.httpBody = body
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
                let (data, urlResponse) = try await session.data(for: request)

                // check the http status code and refresh + retry if we received 401 Unauthorized
                if let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 401 {
                    // If retries are disabled, don't attempt a refresh.
                    guard allowRetry else {
                        throw AuthError.invalidToken
                    }

                    retryCount += 1
                    // Out of retries — surface the failure rather than looping forever.
                    guard retryCount < maxRetries else {
                        throw AuthError.invalidToken
                    }

                    logger.warning("Received 401 Unauthorized, refreshing token (attempt \(retryCount) of \(self.maxRetries))")
                    guard let token = try? await TokenRefreshCoordinator.shared.refreshToken(credentials: credentials) else {
                        throw AuthError.invalidToken
                    }

                    // Persist the refreshed token. handleTokenRefresh invalidates the cached
                    // credentials, so the next loop iteration reads the new token instead of the
                    // stale one. Without this retry the request fails even though the refresh
                    // succeeded, which left the browse screen blank until a manual pull-to-refresh.
                    try await handler.handleTokenRefresh(householdId: credentials.householdId, token: token.0, key: token.1)

                    // Retry the request with the freshly refreshed credentials.
                    continue
                }

                // Successful no-content responses (e.g. unfollow / save / remove via PUT/DELETE)
                // return an empty body — there's nothing to decode.
                if data.isEmpty, let empty = EmptyResponse() as? T {
                    return empty
                }

                do {
                    let response = try decoder.decode(T.self, from: data)
                    return response
                } catch {
//                    print(String(decoding: data, as: UTF8.self))
//                    print("Failed to decode response: \(error)")
                    throw error
                }
            } else {
                retryCount += 1
                if retryCount < maxRetries {
                    try await Task.sleep(for: .microseconds(200 * retryCount))
                } else {
                    throw AuthError.tokenRefreshFailed
                }
            }
        }
        throw AuthError.tokenRefreshFailed
    }

    private func authorizedRequest(from url: URL, token: String) async throws -> URLRequest {
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return urlRequest
    }
}

