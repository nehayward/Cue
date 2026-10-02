import Foundation

/// Songs the watch hands Cue on the iPhone to play there, wherever the
/// iPhone is pointed: the phone itself or its Sonos group. Sent as a
/// message (`WatchSyncMessage.requestData(_:)`), which wakes the iPhone
/// app, and answered with a `WatchPlayReply`.
///
/// Each song carries what the iPhone needs to play it without asking the
/// server again: its id (all a speaker needs) and its stream (what the
/// phone's own player needs), in the order to play them — already
/// shuffled, when the watch was asked to shuffle.
public struct WatchPlayRequest: Codable, Equatable, Sendable {
    public struct Song: Codable, Equatable, Sendable {
        public let source: WatchSource
        /// The id the iPhone's library gives it: a Plex item's Sonos-style
        /// id, a Subsonic id.
        public let id: String
        public let title: String
        public let artist: String
        public let album: String?
        public let artworkURL: URL?
        public let duration: TimeInterval?
        /// The original file on the server.
        public let streamURL: URL
        /// The file's own format (`flac`, `mp3`…).
        public let audioCodec: String?

        public init(source: WatchSource, id: String, title: String, artist: String, album: String?, artworkURL: URL?, duration: TimeInterval?, streamURL: URL, audioCodec: String?) {
            self.source = source
            self.id = id
            self.title = title
            self.artist = artist
            self.album = album
            self.artworkURL = artworkURL
            self.duration = duration
            self.streamURL = streamURL
            self.audioCodec = audioCodec
        }
    }

    /// Songs sent at most: a message has to stay small. A longer list goes
    /// from the song it starts at.
    public static let maximumSongs = 300

    public let songs: [Song]
    /// The one to start at.
    public let startIndex: Int

    /// `songs` from the one at `startIndex`, or as many of them from there
    /// as a message takes.
    public init(songs: [Song], startIndex: Int = 0) {
        let start = songs.indices.contains(startIndex) ? startIndex : 0
        if songs.count > Self.maximumSongs {
            self.songs = Array(songs[start...].prefix(Self.maximumSongs))
            self.startIndex = 0
        } else {
            self.songs = songs
            self.startIndex = start
        }
    }
}

/// The iPhone's answer to a `WatchPlayRequest`: where it's playing, or why
/// it isn't.
public struct WatchPlayReply: Codable, Equatable, Sendable {
    /// The phone, or the name of the speakers.
    public var playingOn: String?
    /// Said on the watch when nothing started.
    public var failure: String?

    public init(playingOn: String? = nil, failure: String? = nil) {
        self.playingOn = playingOn
        self.failure = failure
    }

    public static func failed(_ failure: String) -> WatchPlayReply {
        WatchPlayReply(failure: failure)
    }
}
