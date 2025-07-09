import Foundation
import OSLog

enum AuthError: Error {
    case missingTokenHandler
    case invalidToken
    case tokenRefreshFailed
}

public final class SoundCloudAPI {
    private let logger: Logger = Logger(subsystem: "SoundCloudAPI", category: "SoundCloudAPI")
    private let session: URLSession
    private let decoder: JSONDecoder
    private var accessToken: String?
    private let clientId: String
    private let clientSecret: String
    private let tokenRefreshHandler: TokenRefreshHandler?
    private let maxRetries = 3
    
    public init(
        clientId: String,
        clientSecret: String,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        tokenRefreshHandler: TokenRefreshHandler? = nil
    ) {
        self.session = session
        self.decoder = decoder
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.tokenRefreshHandler = tokenRefreshHandler
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }
    
    public func searchTracks(for query: String, limit: Int = 10, offset: Int = 0) async -> SoundCloudSearchResult? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.soundcloud.com"
        components.path = "/tracks"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "filter", value: "public"),
            URLQueryItem(name: "license", value: "cc-by,cc-by-sa")
        ]
        
        guard let url = components.url else { return nil }
        
        do {
            let searchResult: [SoundCloudTrack] = try await loadAuthorized(url)
            return SoundCloudSearchResult(tracks: searchResult)
        } catch {
            logger.error("Search failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    public func searchPlaylists(for query: String, limit: Int = 10, offset: Int = 0) async -> SoundCloudSearchResult? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.soundcloud.com"
        components.path = "/playlists"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "filter", value: "public"),
            URLQueryItem(name: "license", value: "cc-by,cc-by-sa")
        ]
        
        guard let url = components.url else { return nil }
        
        do {
            let searchResult: [SoundCloudTrack] = try await loadAuthorized(url)
            return SoundCloudSearchResult(tracks: searchResult)
        } catch {
            logger.error("Search failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    
    public func track(for id: String) async -> SoundCloudTrack? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.soundcloud.com"
        components.path = "/tracks/\(id)"
        
        guard let url = components.url else { return nil }
        
        do {
            return try await loadAuthorized(url)
        } catch {
            logger.error("Track lookup failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    public func playlistTracks(for playlistId: String, limit: Int = 50, offset: Int = 0) async -> [SoundCloudTrack]? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.soundcloud.com"
        components.path = "/playlists/\(playlistId)/tracks"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]
        
        guard let url = components.url else { return nil }
        
        do {
            return try await loadAuthorized(url)
        } catch {
            logger.error("Playlist tracks lookup failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    public func getLikedTracks(limit: Int = 50, offset: Int = 0) async -> [SoundCloudTrack]? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.soundcloud.com"
        components.path = "/me/likes/tracks"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        guard let url = components.url else { return nil }
        
        do {
            let tracks: [SoundCloudTrack] = try await authorizedRequestWithDirectToken(url)
            return tracks
        } catch {
            print(error)
            logger.error("Get liked tracks failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func authenticate() async throws {
        let authString = "\(clientId):\(clientSecret)".data(using: .utf8)?.base64EncodedString() ?? ""
        
        var request = URLRequest(url: URL(string: "https://secure.soundcloud.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("Basic \(authString)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            logger.error("Authentication failed with status code: \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }
        
        let authResponse = try decoder.decode(SoundCloudAuthResponse.self, from: data)
        accessToken = authResponse.accessToken
    }
    
    private func loadAuthorized<T: Decodable>(_ url: URL) async throws -> T {
        if accessToken == nil {
            try await authenticate()
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode == 401 {
            try await authenticate()
            request.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")
            let (newData, _) = try await session.data(for: request)
            return try decoder.decode(T.self, from: newData)
        }
        
        if httpResponse.statusCode != 200 {
            logger.error("Request failed with status code: \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }
        
        return try decoder.decode(T.self, from: data)
    }
    
    private func authorizedRequest<T: Decodable>(_ url: URL, method: String = "GET") async throws -> T {
        guard let handler = tokenRefreshHandler else {
            // Fall back to old authentication method if no token handler
            return try await loadAuthorized(url)
        }
        
        var retryCount = 0
        while retryCount < maxRetries {
            if let credentials = try await handler.getCredentials() {
                var request = URLRequest(url: url)
                request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.httpMethod = method
                
                let (data, urlResponse) = try await session.data(for: request)
                
                // Check for 401 Unauthorized response
                if let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 401 {
                    logger.error("SoundCloud authentication failed with 401 Unauthorized")
                    throw AuthError.invalidToken
                }
                
                guard let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                
                return try decoder.decode(T.self, from: data)
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
    
    private func authorizedRequestWithDirectToken<T: Decodable>(_ url: URL, method: String = "GET") async throws -> T {
        // Try to get direct SoundCloud OAuth token from keychain
        if let directToken = try? await tokenRefreshHandler?.getCredentials(for: "SoundCloud") {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(directToken.token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpMethod = method
            
            let (data, urlResponse) = try await session.data(for: request)
            
            // Check for 401 Unauthorized response
            if let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 401 {
                logger.error("SoundCloud direct token authentication failed with 401 Unauthorized")
                throw AuthError.invalidToken
            }
            
            guard let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                logger.error("SoundCloud request failed with status code: \((urlResponse as? HTTPURLResponse)?.statusCode ?? 0)")
                throw URLError(.badServerResponse)
            }
            
            return try decoder.decode(T.self, from: data)
        }
        
        // If no direct token available, throw error
        throw AuthError.invalidToken
    }
}

// MARK: - Models
fileprivate struct SoundCloudAuthResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String
    let scope: String
}
