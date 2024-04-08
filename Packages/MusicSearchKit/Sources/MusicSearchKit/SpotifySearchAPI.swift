import Foundation
import OSLog

final actor SpotifySearchAPI {
    private let logger: Logger = Logger(subsystem: "SpotifySearchAPI", category: "SpotifySearchAPI")
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func search(for query: String, limit: Int = 15, types: Set<SpotifyType>) async -> SpotifyResult? {
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

    func searchSong(for query: String, limit: Int = 25) async -> SpotifyResult? {
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

    func lookupTrack(id: String) async -> SpotifyTrackItems? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/tracks/\(id)"
        guard let url = components.url else { return nil }

        do {
            let spotifyTrack: SpotifyTrackItems = try await loadAuthorized(url)
            return spotifyTrack
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }

    func playlist(id: String) async -> SpotifyPlaylistItems? {
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

    func album(id: String) async -> SpotifyAlbumItems? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/albums/\(id)"
        guard let url = components.url else { return nil }

        do {
            let album: SpotifyAlbumItems = try await loadAuthorized(url)
            return album
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
        request.httpBody = "grant_type=client_credentials&client_id=6569f80e8a74407392c62894a4c10d8c&client_secret=215fa39804da4b2c8032cf76bc81107e".data(using: .utf8)

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

        let response = try decoder.decode(T.self, from: data)
        return response
    }

    private func authorizedRequest(from url: URL) async throws -> URLRequest {
        var urlRequest = URLRequest(url: url)
        let token = try await validToken()
        urlRequest.setValue("Bearer \(token.id)", forHTTPHeaderField: "Authorization")
        return urlRequest
    }

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

            // Normally you'd make a network call here. Could look like this:
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

extension SpotifySearchAPI {
    struct Token {
        let validUntil: Date
        let id: String
        var isValid: Bool { Date.now < validUntil }
    }
}
