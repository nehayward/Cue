import Foundation

/// An artist (ID3 flavor) from a Subsonic-compatible server. `album` is only
/// populated by `getArtist`.
public struct SubsonicArtist: Decodable, Sendable {
    public let id: String
    public let name: String?
    public let coverArt: String?
    public let albumCount: Int?
    public let starred: String?
    public let album: [SubsonicAlbum]?
}
