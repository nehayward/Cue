public struct SpotifyTracks: Decodable {
    public let items: [SpotifyTrackItems]
}

public struct SpotifyTrackItems: Decodable, Identifiable {
    public let id: String
    public let externalUrls: ExternalUrls
    public let href: String
    public let name: String
    public let album: SpotifyAlbum
    public let type: String
    public let uri: String
    public let popularity: Int
}

public struct SpotifyImage: Decodable {
    public let height: Int?
    public let url: String
    public let width: Int?
}

public struct SpotifyAlbum: Decodable {
    public let images: [SpotifyImage]
}
