public struct SpotifyTracks: Equatable, Decodable, Sendable {
    public let items: [SpotifyTrackItem]
}

public struct SpotifyTrackItem: Equatable, Decodable, Identifiable, Sendable {
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
    public var allArtists: String { artists.map(\.name).joined(separator: ", ") }
}

public struct SpotifyImage: Equatable, Decodable, Sendable {
    public let height: Int?
    public let url: String
    public let width: Int?
}

public struct SpotifyAlbum: Equatable, Decodable, Sendable {
    public let images: [SpotifyImage]
}

public struct SpotifyArtistsInfo: Equatable, Decodable, Sendable {
    public let name: String
}

