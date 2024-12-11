import Foundation
import OSLog

public final class SpotifyAPI {

    private let logger: Logger = Logger(subsystem: "SpotifySearchAPI", category: "SpotifySearchAPI")
    private let session: URLSession
    private let decoder: JSONDecoder
    private let tokenManager = TokenManager()
    private let tokenKey: Data?

    public init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        // MARK: Workaround for Spotify Limitation
        let keys: [Data?] = ["grant_type=client_credentials&client_id=29039f2858ac4acda410235f7a9b7996&client_secret=5414507b6dda4f8c8405d1e4e468f506".data(using: .utf8),
                    "grant_type=client_credentials&client_id=6569f80e8a74407392c62894a4c10d8c&client_secret=215fa39804da4b2c8032cf76bc81107e".data(using: .utf8)]
        tokenKey = keys.randomElement()?.map{ $0 }
    }

    public func lookupUser(for userID: String) async -> SpotifyUser? {
        guard let userID = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/users/\(userID)"

        guard let url = components.url else { return nil }

        do {
            let spotifySearch: SpotifyUser = try await loadAuthorized(url)
            return spotifySearch
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }

    public func search(for query: String, limit: Int = 10, types: Set<SpotifyType>) async -> SpotifyResult? {
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
            let spotifySearch: SpotifyResult = try await loadAuthorized(url)
            return spotifySearch
        } catch {
            logger.error("\(error.localizedDescription)")
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
            let spotifySearch: SpotifyResult = try await loadAuthorized(url)
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
            let spotifySearch: SpotifyResult = try await loadAuthorized(url)
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
            let spotifyTrack: SpotifyTrackItem = try await loadAuthorized(url)
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
            let spotifyPlaylist: SpotifyPlaylistItems = try await loadAuthorized(url)
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
            let spotifyPlaylist: SpotifyUserPlaylistsResponse = try await loadAuthorized(url)
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
            let spotifyPlaylist: SpotifyPlaylistsFullContainer = try await loadAuthorized(url)
            return spotifyPlaylist
        } catch {
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
            let album: SpotifyAlbumItem = try await loadAuthorized(url)
            return album
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }

    public func albumDetails(id: String) async -> SpotifyAlbumDetails? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/albums/\(id)"
        components.queryItems = [
//            URLQueryItem(name: "market", value: ""),
            URLQueryItem(name: "limit", value: "50")
        ]

        guard let url = components.url else { return nil }

        do {
            let spotifyAlbum: SpotifyAlbumDetails = try await loadAuthorized(url)
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
            let artist: SpotifyArtistsItems = try await loadAuthorized(url)
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
            let spotifyArtistTopTracks: SpotifyArtistTopTracks = try await loadAuthorized(url)
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
            let tracks: SpotifyArtistAlbums = try await loadAuthorized(url)
            return tracks
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }

    func getToken() async -> SpotifyTokenResponse? {
        guard let URL = URL(string: "https://accounts.spotify.com/api/token") else { return nil }
        var request = URLRequest(url: URL)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = tokenKey

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            let spotifySearch = try decoder.decode(SpotifyTokenResponse.self, from: data)
            return spotifySearch
        } catch {
            logger.error("\(error.localizedDescription)")
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

    func loadAuthorized<T: Decodable>(_ url: URL, allowRetry: Bool = true) async throws -> T {
        let request = try await authorizedRequest(from: url)
        let (data, urlResponse) = try await session.data(for: request)

        // check the http status code and refresh + retry if we received 401 Unauthorized
        if let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 401 {
            if allowRetry {
                _ = try await refreshToken()
                return try await loadAuthorized(url, allowRetry: false)
            }

            throw AuthError.invalidToken
        }

        do {
            let response = try decoder.decode(T.self, from: data)
            return response
        } catch {
            print(T.self)
            print(error)
            logger.error("Failed to decode ⚠️")
//            assertionFailure(String(decoding: data, as: UTF8.self))
            throw error
        }
    }

    private func authorizedRequest(from url: URL) async throws -> URLRequest {
        var urlRequest = URLRequest(url: url)
        let token = try await validToken()
        urlRequest.setValue("Bearer \(token.id)", forHTTPHeaderField: "Authorization")
        return urlRequest
    }

    // Update the validToken method
    func validToken() async throws -> Token {
        return try await tokenManager.getValidToken(refreshToken: refreshToken)
    }

    // Update the refreshToken method
    func refreshToken() async throws -> Token {
        guard let response = await getToken() else {
            throw AuthError.missingToken
        }
        
        return Token(validUntil: Date.now.addingTimeInterval(TimeInterval(response.expiresIn)), id: response.accessToken)
    }
}

extension SpotifyAPI {
    struct Token {
        let validUntil: Date
        let id: String
        var isValid: Bool { Date.now < validUntil }
    }
    
    actor TokenManager {
        private var currentToken: Token?
        private var refreshTask: Task<Token, Error>?
        
        func getValidToken(refreshToken: @escaping () async throws -> Token) async throws -> Token {
            if let token = currentToken, token.isValid {
                return token
            }
            
            return try await refreshTokenIfNeeded(refreshToken: refreshToken)
        }
        
        private func refreshTokenIfNeeded(refreshToken: @escaping () async throws -> Token) async throws -> Token {
            if let task = refreshTask {
                return try await task.value
            }
            
            let task = Task {
                defer { refreshTask = nil }
                let newToken = try await refreshToken()
                currentToken = newToken
                return newToken
            }
            
            refreshTask = task
            return try await task.value
        }
    }
}

