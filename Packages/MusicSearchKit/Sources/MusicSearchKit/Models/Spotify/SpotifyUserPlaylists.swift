import Foundation

public struct SpotifyUserPlaylistsResponse: Decodable {
    public let href: String?
    public let items: [SpotifyUserPlaylists?]
    public let limit: Int
    public let next: String?
    public let offset: Int
    public let previous: String?
    public let total: Int
}

public struct SpotifyUserPlaylists: Decodable {
   public let collaborative: Bool
   public let description: String
   public let externalUrls: ExternalUrls
   public let href: String?
   public let id: String
   public let images: [SpotifyImage]?
   public let name: String
   public let owner: Owner?
   public let snapshotId: String
   public let tracks: PlaylistTracks
   public let type: String
   public let uri: String

   /// Whether the authenticated user can add/remove tracks: they own it or it's collaborative.
   public func isEditable(by userID: String) -> Bool {
       collaborative || owner?.id == userID
   }
}
