import Foundation

/// A playlist from a Subsonic-compatible server. `entry` is only populated by
/// `getPlaylist`.
public struct SubsonicPlaylist: Decodable, Sendable {
    public let id: String
    public let name: String?
    public let owner: String?
    public let songCount: Int?
    /// Seconds.
    public let duration: Int?
    public let coverArt: String?
    public let entry: [SubsonicSong]?
}
