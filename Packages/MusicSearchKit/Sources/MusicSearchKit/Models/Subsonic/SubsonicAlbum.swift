import Foundation

/// An album (ID3 flavor) from a Subsonic-compatible server. `song` is only
/// populated by `getAlbum`.
public struct SubsonicAlbum: Decodable, Sendable {
    public let id: String
    public let name: String?
    /// Some servers return `title` instead of (or alongside) `name`.
    public let title: String?
    public let artist: String?
    public let artistId: String?
    public let coverArt: String?
    public let songCount: Int?
    /// Seconds.
    public let duration: Int?
    public let year: Int?
    public let starred: String?
    public let song: [SubsonicSong]?

    public var displayName: String { name ?? title ?? "" }
}
