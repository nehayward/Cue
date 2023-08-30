import Foundation
import OSLog

final class SpotifySearchAPI {
    private let logger: Logger = Logger(subsystem: "SpotifySearchAPI", category: "SpotifySearchAPI")
    private let session: URLSession
    private let decoder: JSONDecoder

    private var token: String? = nil

    init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    func search(for query: String, limit: Int = 25) async -> SpotifyResult? {
        if token == nil {
            self.token = await getToken()?.accessToken
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "playlist"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components.url, let token else { return nil }

        //        logger.trace("\(url.absoluteString)")

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = ["Authorization": "Bearer \(token)"]

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let spotifySearch = try decoder.decode(SpotifyResult.self, from: data)
            return spotifySearch
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }

    func searchSong(for query: String, limit: Int = 25) async -> SpotifyResult? {
        if token == nil {
            self.token = await getToken()?.accessToken
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components.url, let token else { return nil }

        //        logger.trace("\(url.absoluteString)")

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = ["Authorization": "Bearer \(token)"]

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let spotifySearch = try decoder.decode(SpotifyResult.self, from: data)
            return spotifySearch
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }

    func lookupTrack(id: String) async -> SpotifyTrackItems? {
        if token == nil {
            self.token = await getToken()?.accessToken
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/tracks/\(id)"
        guard let url = components.url, let token else { return nil }
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = ["Authorization": "Bearer \(token)"]

        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let spotifyTrack = try decoder.decode(SpotifyTrackItems.self, from: data)
            return spotifyTrack
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
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let spotifySearch = try decoder.decode(SpotifyTokenResponse.self, from: data)
            return spotifySearch
        } catch {
            logger.error("\(error.localizedDescription)")
            return nil
        }
    }
}
