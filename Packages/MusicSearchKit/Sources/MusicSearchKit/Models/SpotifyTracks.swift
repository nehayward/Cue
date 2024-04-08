public struct SpotifyTracks: Decodable, Sendable {
    public let items: [SpotifyTrackItems]
}

public struct SpotifyTrackItems: Decodable, Identifiable, Sendable {
    public let id: String
    public let href: String
    public let name: String
    public let album: SpotifyAlbum
    public let artists: [SpotifyArtistsInfo]
    public let externalUrls: ExternalUrls
    public let externalIds: SpotifyExternalIDS
    public let type: String
    public let uri: String
    public let popularity: Int
}

public struct SpotifyImage: Decodable, Sendable {
    public let height: Int?
    public let url: String
    public let width: Int?
}

public struct SpotifyAlbum: Decodable, Sendable {
    public let images: [SpotifyImage]
}

public struct SpotifyArtistsInfo: Decodable, Sendable {
    public let name: String
}

