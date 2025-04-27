import Foundation
import OSLog

public final class SoundCloudAPI {
    private let logger: Logger = Logger(subsystem: "SoundCloudAPI", category: "SoundCloudAPI")
    private let session: URLSession
    private let decoder: JSONDecoder
    private var accessToken: String?
    private let clientId: String
    private let clientSecret: String
    
    public init(clientId: String, clientSecret: String, session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
        self.clientId = clientId
        self.clientSecret = clientSecret
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
}

// MARK: - Models
fileprivate struct SoundCloudAuthResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String
    let scope: String
}
