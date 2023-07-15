import Foundation
import OSLog

final class AppleMusicSearchAPI {
    private let logger: Logger = Logger(subsystem: "AppleMusicSearchAPI", category: "AppleMusicSearchAPI")
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    func search(for query: String, limit: Int = 25) async -> [ItunesResult] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components.url else { return [] }

        logger.trace("\(url.absoluteString)")

        let request = URLRequest(url: url)
        guard let (data, _) = try? await session.data(for: request) else {
            return []
        }
        
        do {
            let musicSearch = try decoder.decode(ItunesMusicSearch.self, from: data)
            return musicSearch.results
        } catch {
            print(error)
            return []
        }
    }
}
