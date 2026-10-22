import Foundation

/// What Cue on the iPhone is playing, for the watch's home while the watch
/// itself isn't: the song (or the book, by its author), where it plays —
/// the iPhone or a Sonos group — whether it's playing, and a small copy of
/// the cover. The iPhone sends it while the watch app is open, as it
/// changes, and in answer to the watch asking (`WatchSyncMessage`).
public struct WatchPhoneNowPlaying: Codable, Equatable, Sendable {
    public var title: String
    public var artist: String?
    /// Where it plays: the iPhone's name, or the Sonos group's.
    public var destination: String
    /// On a Sonos group rather than the iPhone itself.
    public var isOnSpeaker: Bool
    public var isPlaying: Bool
    /// The cover as a small JPEG, made on the iPhone: the watch can't
    /// always reach the cover's own URL (a speaker's, a server's).
    public var artwork: Data?

    public init(title: String, artist: String? = nil, destination: String, isOnSpeaker: Bool = false, isPlaying: Bool, artwork: Data? = nil) {
        self.title = title
        self.artist = artist
        self.destination = destination
        self.isOnSpeaker = isOnSpeaker
        self.isPlaying = isPlaying
        self.artwork = artwork
    }
}
