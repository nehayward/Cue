import Foundation

/// The queue Cue on the iPhone plays from, for the watch's player of the
/// iPhone's playback: the song playing and the ones after it, here or on
/// the Sonos group, as far as `limit`. The watch asks for it as its Up Next
/// opens and again when the iPhone says the queue moved
/// (`WatchPhoneNowPlaying.queuePosition`, `queueCount`); a tap asks the
/// iPhone to play that song (`WatchSyncMessage.playQueueRequest`).
public struct WatchPhoneQueue: Codable, Equatable, Sendable {
    public struct Song: Codable, Equatable, Sendable, Identifiable {
        /// Its place in the queue, from 1: what a tap asks the iPhone to
        /// play.
        public var position: Int
        public var title: String
        public var artist: String?

        public var id: Int { position }

        public init(position: Int, title: String, artist: String? = nil) {
            self.position = position
            self.title = title
            self.artist = artist
        }
    }

    /// From the song playing on (or the one the queue waits on), in order.
    public var songs: [Song]
    /// The position of the song playing; nil while the queue waits, a
    /// station playing in front of it or the speaker on radio or TV.
    public var current: Int?
    /// How many songs the whole queue holds, past the ones sent too.
    public var count: Int

    /// The most songs sent: a message stays a few KB, and a watch list
    /// longer than this is more scrolling than anyone does.
    public static let limit = 50

    public init(songs: [Song], current: Int?, count: Int) {
        self.songs = songs
        self.current = current
        self.count = count
    }

    /// The queue doesn't play: what plays is in front of it.
    public var isWaiting: Bool { current == nil }

    /// How many songs come after the last one sent.
    public var remaining: Int {
        max(0, count - (songs.last?.position ?? 0))
    }
}
