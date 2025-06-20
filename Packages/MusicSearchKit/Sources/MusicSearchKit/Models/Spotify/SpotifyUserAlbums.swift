import Foundation

public struct SpotifyUserAlbumResponse: Decodable {
    public let href: String?
    public let items: [SpotifyUserAlbums?]
    public let limit: Int
    public let next: String?
    public let offset: Int
    public let previous: String?
    public let total: Int
}

public struct SpotifyUserAlbums: Decodable {
    public let album: SpotifyAlbumItem
    public let addedAt: Date?
}
