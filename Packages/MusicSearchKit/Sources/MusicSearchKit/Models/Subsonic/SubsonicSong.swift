import Foundation

/// A song ("child" element) from a Subsonic-compatible server
/// (Subsonic, Navidrome, Airsonic, Gonic, …).
public struct SubsonicSong: Decodable, Sendable {
    public let id: String
    public let title: String?
    public let album: String?
    public let albumId: String?
    public let artist: String?
    public let artistId: String?
    public let coverArt: String?
    /// Seconds.
    public let duration: Int?
    public let bitRate: Int?
    public let suffix: String?
    public let contentType: String?
    public let track: Int?
    public let year: Int?
    /// Present (an ISO date) when the song is starred by the current user.
    public let starred: String?
}
