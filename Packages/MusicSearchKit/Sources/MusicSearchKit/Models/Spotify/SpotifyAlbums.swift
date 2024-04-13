public struct SpotifyAlbums: Decodable, Sendable {
    public let items: [SpotifyAlbumItem]
}

public struct SpotifyAlbumItem: Decodable, Identifiable, Sendable {
    public let id: String
    public let externalUrls: ExternalUrls
    public let href: String
    public let name: String
    public let artists: [SpotifyArtistsInfo]
    public let images: [SpotifyImage]
    public let type: String
    public let uri: String
    public var allArtists: String { artists.map(\.name).joined(separator: ", ") }
}

public struct SpotifyAlbumTracks: Decodable, Sendable {
    public let items: [SpotifyAlbumTrackItems]
}

public struct SpotifyAlbumTrackItems: Decodable, Identifiable, Sendable {
    public let id: String
    public let href: String
    public let name: String
    public let artists: [SpotifyArtistsInfo]
    public let externalUrls: ExternalUrls
    public let externalIds: SpotifyExternalIDS?
    public let type: String
    public let uri: String
    public let durationMs: Int
    public var allArtists: String { artists.map(\.name).joined(separator: ", ") }
}
