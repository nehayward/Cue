import Foundation

public final class TidalAPI {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    public func search(for query: String, limit: Int = 10) async -> TidalResult? {
        if query.count < 1 { return nil }
        
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openapi.tidal.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US"),
        ]

        guard let url = components.url else {
            return nil
        }

        do {
            guard let spotifySearch: TidalResult? = try await loadAuthorized(url) else { return nil }
            return spotifySearch
        } catch {

            return nil
        }
    }

//    public func track(with id: String) async -> SpotifyTrackItem? {
//        var components = URLComponents()
//        components.scheme = "https"
//        components.host = "api.spotify.com"
//        components.path = "/v1/tracks/\(id)"
//        guard let url = components.url else { return nil }
//
//        do {
//            let spotifyTrack: SpotifyTrackItem = try await loadAuthorized(url)
//            return spotifyTrack
//        } catch {
//
//            return nil
//        }
//    }
//
//    public func playlist(id: String) async -> SpotifyPlaylistItems? {
//        var components = URLComponents()
//        components.scheme = "https"
//        components.host = "api.spotify.com"
//        components.path = "/v1/playlists/\(id)"
//        guard let url = components.url else { return nil }
//
//        do {
//            let spotifyPlaylist: SpotifyPlaylistItems = try await loadAuthorized(url)
//            return spotifyPlaylist
//        } catch {
//            return nil
//        }
//    }

    public func track(with id: String) async -> TidalTrackResource? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openapi.tidal.com"
        components.path = "/tracks/\(id)"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US"),
        ]

        guard let url = components.url else {
            return nil
        }

        struct TrackResult: Codable {
            let resource: TidalTrackResource
        }

        guard let trackResult: TrackResult = try? await loadAuthorized(url) else { return nil }
        return trackResult.resource
    }

    public func album(with id: String) async -> TidalAlbumResource? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openapi.tidal.com"
        components.path = "/albums/\(id)"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US"),
        ]

        guard let url = components.url else {
            return nil
        }

        struct AlbumResult: Codable {
            let resource: TidalAlbumResource
        }

        guard let trackResult: AlbumResult = try? await loadAuthorized(url) else { return nil }
        return trackResult.resource
    }

    public func albumSongs(id: String) async -> [TidalTrackResource] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openapi.tidal.com"
        components.path = "/albums/\(id)/items"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US"),
        ]

        guard let url = components.url else {
            return []
        }

        struct AlbumResult: Codable {
            let data: [TidalTrackEntry]
        }

        guard let album: AlbumResult = try? await loadAuthorized(url) else { return [] }
        return album.data.map { $0.resource }
    }

    public func artistSongs(id: String) async -> [TidalTrackResource] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openapi.tidal.com"
        components.path = "/artists/\(id)/tracks"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US"),
        ]

        guard let url = components.url else {
            return []
        }

        struct AlbumResult: Codable {
            let data: [TidalTrackEntry]
        }

        guard let album: AlbumResult = try? await loadAuthorized(url) else { return [] }
        return album.data.map { $0.resource }
    }

    public func artistAlbums(id: String) async -> [TidalAlbumResource] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openapi.tidal.com"
        components.path = "/artists/\(id)/albums"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US"),
        ]

        guard let url = components.url else {
            return []
        }

        struct AlbumResult: Codable {
            let data: [TidalAlbumEntry]
        }

        guard let album: AlbumResult = try? await loadAuthorized(url) else { return [] }
        return album.data.map { $0.resource }
    }

    public func artist(with id: String) async -> TidalArtistResource? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "openapi.tidal.com"
        components.path = "/artists/\(id)"
        components.queryItems = [
            URLQueryItem(name: "countryCode", value: Locale.current.region?.identifier ?? "US"),
        ]

        guard let url = components.url else {
            return nil
        }

        struct ArtistResult: Codable {
            let resource: TidalArtistResource
        }

        guard let trackResult: ArtistResult = try? await loadAuthorized(url) else { return nil }
        return trackResult.resource
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
            print("Failed to decode ⚠️")
            print(String(decoding: data, as: UTF8.self))
            assertionFailure(String(decoding: data, as: UTF8.self))
            throw error
        }
    }

    private func authorizedRequest(from url: URL) async throws -> URLRequest {
        var urlRequest = URLRequest(url: url)
        let token = try await validToken()
        urlRequest.setValue("Bearer \(token.id)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/vnd.tidal.v1+json", forHTTPHeaderField: "Content-Type")

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
