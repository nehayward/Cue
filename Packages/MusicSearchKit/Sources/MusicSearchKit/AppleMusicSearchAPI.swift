import Foundation

public final class AppleMusicSearchAPI {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    public func search(for query: String, limit: Int = 25, entities: Set<AppleEntity> = [.song]) async -> [ItunesResult] {
        let entities = entities.map { $0.rawValue }.joined(separator: ", ")
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: entities),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = components.url else { return [] }

//        logger.trace("\(url.absoluteString)")

        let request = URLRequest(url: url)
        guard let (data, _) = try? await session.data(for: request) else {
            return []
        }
        
        do {
            let musicSearch = try decoder.decode(ItunesMusicSearch.self, from: data)
            return musicSearch.results
        } catch {
            return []
        }
    }

    public func lookupTrack(id: String) async -> ItunesResult? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
        ]
        guard let url = components.url else { return nil }

        let request = URLRequest(url: url)
        guard let (data, _) = try? await session.data(for: request) else {
            return nil
        }

        do {
            let musicSearch = try decoder.decode(ItunesMusicSearch.self, from: data)
            return musicSearch.results.first
        } catch {
            return nil
        }
    }

    /// Looks up any Apple Music entity (track, album/collection, artist) by ID
    /// against the public iTunes Search API. No auth/entitlement required.
    /// Pass `preferredWrapperType` ("track", "collection", "artist") so the
    /// best-matching row is picked when iTunes returns multiple wrapper types.
    public func lookup(id: String, preferredWrapperType: String? = nil) async -> ITunesLookupItem? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        guard let url = components.url else { return nil }

        guard let (data, _) = try? await session.data(for: URLRequest(url: url)),
              let response = try? decoder.decode(ITunesLookupResponse.self, from: data) else {
            return nil
        }
        if let preferredWrapperType,
           let match = response.results.first(where: { $0.wrapperType == preferredWrapperType }) {
            return match
        }
        return response.results.first
    }
}
