import Foundation

/// What Cue on the iPhone is playing, for the watch's home while the watch
/// itself isn't: the song (or the book, by its author), where it plays —
/// the iPhone or a Sonos group — whether it's playing, which way it can
/// skip, and a small copy of the cover. The iPhone sends it while the watch
/// app is open, as it changes, and in answer to the watch asking
/// (`WatchSyncMessage`).
public struct WatchPhoneNowPlaying: Codable, Equatable, Sendable {
    public var title: String
    public var artist: String?
    /// Where it plays: the iPhone's name, or the Sonos group's.
    public var destination: String
    /// On a Sonos group rather than the iPhone itself.
    public var isOnSpeaker: Bool
    public var isPlaying: Bool
    /// One of the iPhone's books: Previous and Next skip back 15 s and
    /// ahead 30 s, as on the iPhone's player.
    public var isBook: Bool
    /// Previous does something: none for a live station.
    public var canGoBack: Bool
    /// Next does something: none at the end of the queue or on a live
    /// station.
    public var hasNext: Bool
    /// The cover as a small JPEG, made on the iPhone: the watch can't
    /// always reach the cover's own URL (a speaker's, a server's).
    public var artwork: Data?

    public init(title: String, artist: String? = nil, destination: String, isOnSpeaker: Bool = false, isPlaying: Bool, isBook: Bool = false, canGoBack: Bool = true, hasNext: Bool = true, artwork: Data? = nil) {
        self.title = title
        self.artist = artist
        self.destination = destination
        self.isOnSpeaker = isOnSpeaker
        self.isPlaying = isPlaying
        self.isBook = isBook
        self.canGoBack = canGoBack
        self.hasNext = hasNext
        self.artwork = artwork
    }

    private enum CodingKeys: String, CodingKey {
        case title, artist, destination, isOnSpeaker, isPlaying, isBook, canGoBack, hasNext, artwork
    }

    /// An iPhone a version behind sends no skips: music, both ways open.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        destination = try container.decode(String.self, forKey: .destination)
        isOnSpeaker = try container.decode(Bool.self, forKey: .isOnSpeaker)
        isPlaying = try container.decode(Bool.self, forKey: .isPlaying)
        isBook = try container.decodeIfPresent(Bool.self, forKey: .isBook) ?? false
        canGoBack = try container.decodeIfPresent(Bool.self, forKey: .canGoBack) ?? true
        hasNext = try container.decodeIfPresent(Bool.self, forKey: .hasNext) ?? true
        artwork = try container.decodeIfPresent(Data.self, forKey: .artwork)
    }
}

/// A press on the watch's player for the iPhone's playback, carried out by
/// the iPhone on what its player shows (`PlaybackRoute.presented`).
public enum WatchPhoneCommand: String, Sendable, CaseIterable {
    case togglePlayPause
    /// The song before, or back 15 s in a book.
    case previous
    /// The next song, or ahead 30 s in a book.
    case next
}
