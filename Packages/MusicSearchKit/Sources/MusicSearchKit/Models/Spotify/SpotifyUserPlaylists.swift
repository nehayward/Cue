import Foundation

public struct SpotifyUserPlaylistsResponse: Decodable {
    public let href: String?
    public let items: [UserPlaylists]
    public let limit: Int
    public let next: String?
    public let offset: Int
    public let previous: String?
    public let total: Int
}

public struct UserPlaylists: Decodable {
   public let collaborative: Bool
   public let description: String
   public let externalUrls: ExternalUrls
   public let href: String?
   public let id: String
   public let images: [SpotifyImage]?
   public let name: String
   public let snapshotId: String
   public let tracks: PlaylistTracks
   public let type: String
   public let uri: String
}
