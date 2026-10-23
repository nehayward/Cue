import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An author as Audible has them, from Audnexus (`api.audnex.us/authors`):
/// their picture, their biography, the genres they write in and the
/// authors read alongside them. For an author's page, whose servers often
/// keep no picture or biography of their own.
public struct AudnexusAuthor: Codable, Sendable, Equatable {
    public let asin: String
    public let name: String
    public let description: String?
    public let image: String?
    public let genres: [Genre]?
    public let similar: [Similar]?

    public struct Genre: Codable, Sendable, Equatable {
        public let name: String
        /// "genre", or "tag" for a finer one.
        public let type: String?
    }

    public struct Similar: Codable, Sendable, Equatable {
        public let asin: String
        public let name: String
    }

    public var imageURL: URL? {
        image.flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }
}

extension AudnexusAPI {
    /// What Audnexus said about an author.
    public enum AuthorAnswer: Sendable {
        case found(AudnexusAuthor)
        /// It answered, and knows no author by that name.
        case notFound
        /// It couldn't be asked.
        case unreachable
    }

    /// The author called `name`: Audnexus's search by name, the first whose
    /// name is the same, then their record.
    public static func author(named name: String, region: String = "us") async -> AuthorAnswer {
        guard var search = URLComponents(string: "https://api.audnex.us/authors") else { return .unreachable }
        search.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "region", value: region)]
        guard let searchURL = search.url else { return .unreachable }
        guard let (data, status) = await get(searchURL) else { return .unreachable }
        guard status == 200 else { return status == 404 ? .notFound : .unreachable }
        let matches = (try? JSONDecoder().decode([AudnexusAuthor.Similar].self, from: data)) ?? []
        guard let match = matches.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            return .notFound
        }

        guard var record = URLComponents(string: "https://api.audnex.us/authors/\(match.asin)") else { return .unreachable }
        record.queryItems = [URLQueryItem(name: "region", value: region)]
        guard let recordURL = record.url, let (body, recordStatus) = await get(recordURL) else { return .unreachable }
        guard recordStatus == 200 else { return recordStatus == 404 ? .notFound : .unreachable }
        guard let author = try? JSONDecoder().decode(AudnexusAuthor.self, from: body) else { return .unreachable }
        return .found(author)
    }

    private static func get(_ url: URL) async -> (Data, Int)? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        return (data, http.statusCode)
    }
}
