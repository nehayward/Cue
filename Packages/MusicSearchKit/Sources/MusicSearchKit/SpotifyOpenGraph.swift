import Foundation

/// Auth-free Spotify metadata via Open Graph + oEmbed.
public struct SpotifyOpenGraph: Sendable, Equatable {
    public let title: String?
    public let description: String?
    public let image: URL?
    public let oembedAuthor: String?

    /// The artist or playlist owner extracted from `og:description`.
    /// Spotify pages use the format `Title · Author · Year` — index 1 is the
    /// performer for tracks/albums and the curator for playlists.
    public var resolvedAuthor: String? {
        let parts = (description ?? "")
            .components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if parts.count >= 2 { return parts[1] }
        return oembedAuthor
    }
}

public final class SpotifyOpenGraphAPI {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    public func lookup(url: URL) async -> SpotifyOpenGraph {
        async let pageOG = OpenGraphScraper.fetch(url: url, session: session)
        async let oe = fetchOEmbed(url: url)

        let og = await pageOG
        let oembed = await oe

        return SpotifyOpenGraph(
            title: og.title ?? oembed.title,
            description: og.description,
            image: og.image ?? oembed.thumbnail_url.flatMap(URL.init(string:)),
            oembedAuthor: oembed.author_name
        )
    }

    private struct OEmbedResponse: Decodable {
        let title: String?
        let thumbnail_url: String?
        let author_name: String?
    }

    private func fetchOEmbed(url: URL) async -> OEmbedResponse {
        var components = URLComponents(string: "https://open.spotify.com/oembed")!
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        guard let endpoint = components.url,
              let (data, _) = try? await session.data(for: URLRequest(url: endpoint)),
              let decoded = try? decoder.decode(OEmbedResponse.self, from: data) else {
            return OEmbedResponse(title: nil, thumbnail_url: nil, author_name: nil)
        }
        return decoded
    }
}
