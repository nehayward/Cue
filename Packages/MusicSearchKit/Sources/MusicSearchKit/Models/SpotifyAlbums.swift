public struct SpotifyAlbums: Decodable, Sendable {
    public let items: [SpotifyAlbumItems]
}

public struct SpotifyAlbumItems: Decodable, Identifiable, Sendable {
    public let id: String
    public let externalUrls: ExternalUrls
    public let href: String
    public let name: String
    public let artists: [SpotifyArtistsInfo]
    public let images: [SpotifyImage]
    public let type: String
    public let uri: String
}
