public struct SpotifyArtists: Decodable, Sendable {
    public let items: [SpotifyArtistsItems]
}

public struct SpotifyArtistsItems: Decodable, Identifiable, Sendable {
    public let id: String
    public let externalUrls: ExternalUrls
    public let href: String
    public let name: String
    public let images: [SpotifyImage]
    public let type: String
    public let uri: String
    public let popularity: Int
}
