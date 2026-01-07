import Foundation
import OSLog

// Empty response type for PUT/DELETE operations that don't return content
private struct EmptyResponse: Codable {}

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
            URLQueryItem(name: "limit", value: "\(limit)")
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
            URLQueryItem(name: "limit", value: "\(limit)")
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
        components.queryItems = [
            .init(name: "offset", value: "\(offset)"),
            .init(name: "limit", value: "\(limit)")
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
            .init(name: "limit", value: "\(limit)")
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
            .init(name: "limit", value: "\(limit)")
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
            .init(name: "limit", value: "\(limit)")
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
//            URLQueryItem(name: "market", value: ""),
            URLQueryItem(name: "limit", value: "50")
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
            URLQueryItem(name: "include_groups", value: "album")
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

    enum AuthError: Error {
        case missingToken
        case invalidToken
        case tokenRefreshFailed
        case missingTokenHandler
    }

    func authorizedRequest<T: Decodable>(_ url: URL, method: String = "GET", allowRetry: Bool = true) async throws -> T {
        guard let handler = tokenRefreshHandler else {
            throw AuthError.missingTokenHandler
        }
        
        var retryCount = 0
        while retryCount < maxRetries {
            if let credentials = try await handler.getCredentials() {
                var request = try await authorizedRequest(from: url, token: credentials.token)
                request.httpMethod = method
                let (data, urlResponse) = try await session.data(for: request)

                // check the http status code and refresh + retry if we received 401 Unauthorized
                if let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 401 {
                    if allowRetry {
                        print("Received 401 Unauthorized, attempting token refresh")
                        retryCount += 1
                        if retryCount < maxRetries {
                            guard let token = try? await TokenRefreshCoordinator.shared.refreshToken(credentials: credentials) else {
                                throw AuthError.invalidToken
                            }
                            try await handler.handleTokenRefresh(householdId: credentials.householdId, token: token.0, key: token.1)
                        }
                    }
                    throw AuthError.invalidToken
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

