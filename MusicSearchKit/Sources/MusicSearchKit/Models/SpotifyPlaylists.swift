public struct SpotifyPlaylists: Decodable {
    public let items: [SpotifyPlaylistItems]
}

public struct SpotifyPlaylistItems: Decodable, Identifiable {
    public let id: String
    let collaborative: Bool
    let description: String
    public let externalUrls: ExternalUrls
    public let href: String
    public let images: [Image]
    public let name: String
    public let owner: Owner
    let primaryColor: String?
    let `public`: Bool?
    let snapshotId: String
    let tracks: Tracks
    public let type: String
    public let uri: String
}

public struct ExternalUrls: Decodable {
    public let spotify: String
}

public struct Image: Decodable {
    public let height: Int?
    public let url: String
    public let width: Int?
}

public struct Owner: Decodable {
    public let displayName: String
    let externalUrls: ExternalUrls
    public let href: String
    let id: String
    let type: String
    public let uri: String
}

public struct Tracks: Decodable {
    let href: String
    let total: Int
}
