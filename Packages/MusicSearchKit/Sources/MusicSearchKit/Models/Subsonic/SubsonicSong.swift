import Foundation

/// A song ("child" element) from a Subsonic-compatible server
/// (Subsonic, Navidrome, Airsonic, Gonic, …).
public struct SubsonicSong: Codable, Sendable {
    public let id: String
    public let title: String?
    public let album: String?
    public let albumId: String?
    public let artist: String?
    public let artistId: String?
    public let coverArt: String?
    /// Seconds.
    public let duration: Int?
    public let suffix: String?
    /// Present (an ISO date) when the song is starred by the current user.
    public let starred: String?
    public let year: Int?
    public let track: Int?
    public let discNumber: Int?
    public let playCount: Int?
    /// When the server first saw the file, as an ISO 8601 timestamp.
    public let created: String?
}
