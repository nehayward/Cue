public struct SpotifyPlaylists: Decodable, Sendable {
    public let items: [SpotifyPlaylistItems?]
}

public struct SpotifyPlaylistItems: Decodable, Identifiable, Sendable {
    public let id: String
    let collaborative: Bool
    let description: String
    public let externalUrls: ExternalUrls
    public let href: String
    public let images: [SpotifyImage]?
    public let name: String
    public let owner: Owner
    let primaryColor: String?
    let `public`: Bool?
    let snapshotId: String
    public let tracks: PlaylistTracks
    public let type: String
    public let uri: String
}

public struct ExternalUrls: Equatable, Decodable, Sendable {
    public let spotify: String?
}

public struct Owner: Decodable, Sendable {
    public let displayName: String
    let externalUrls: ExternalUrls
    public let href: String
    let id: String
    let type: String
    public let uri: String
}

public struct PlaylistTracks: Decodable, Sendable {
    let href: String
    let total: Int
    public let items: [SpotifyPlaylistItemContainer]?
}

public struct SpotifyPlaylistsFullContainer: Decodable, Sendable {
    public let items: [SpotifyPlaylistItemContainer]
    public let total: Int
}

public struct SpotifyPlaylistItemContainer: Decodable, Sendable {
    public let track: SpotifyAlbumTrackItems
}
