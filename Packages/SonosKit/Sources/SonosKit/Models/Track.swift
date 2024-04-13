import Foundation

/// An observable class representing a track in a music service.
@Observable
public final class Track: Identifiable, Sendable {
    private let queue = DispatchQueue(label: "Track.\(UUID().uuidString)")

    @ObservationIgnored private var _playbackPosition: TimeInterval = .zero

    /// The unique identifier of the track.
    public let trackID: String
    /// The name of the track.
    public var name: String
    /// The artist of the track.
    public var artist: String
    /// The album of the track.
    public var album: String
    /// The URL for the track's artwork.
    public var artworkURL: URL?
    /// The music service associated with the track.
    public var musicService: MusicService
    /// The duration of the track, in seconds.
    public var duration: TimeInterval
    /// The position of the track in a playlist or queue.
    public var position: Int
    /// The URL for the album art specific to Sonos service.
    public var sonosAlbumArtURL: URL?

    public var TVMode: Bool

    public var metadata: Metadata?

    /// The identifier for `Identifiable` conformance.
    public var id: String { trackID }
    /// The playback position of the track, thread-safe.
    public var playbackPosition: TimeInterval {
        get { queue.sync { _playbackPosition } }
        set { queue.sync { _playbackPosition = newValue } }
    }

    /// Initializes a new `Track` instance.
    /// - Parameters:
    ///   - trackID: The unique identifier for the track.
    ///   - name: The name of the track.
    ///   - artist: The artist of the track.
    ///   - album: The album of the track.
    ///   - artworkURL: The URL for the track's artwork.
    ///   - musicService: The music service associated with the track.
    ///   - duration: The duration of the track, in seconds.
    ///   - playbackPosition: The current playback position of the track.
    ///   - position: The position of the track in a playlist or queue.
    ///   - sonosAlbumArtURL: The URL for the album art specific to Sonos service.
    public init(
        trackID: String,
        name: String = "",
        artist: String = "",
        album: String = "",
        artworkURL: URL? = nil,
        musicService: MusicService = .unknown,
        duration: TimeInterval = .zero,
        playbackPosition: TimeInterval = .zero,
        position: Int = 0,
        sonosAlbumArtURL: URL? = nil,
        metadata: Metadata? = nil,
        TVMode: Bool = false
    ) {
        self.trackID = trackID
        self.name = name
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.musicService = musicService
        self.duration = duration
        self._playbackPosition = playbackPosition
        self.position = position
        self.sonosAlbumArtURL = sonosAlbumArtURL
        self.TVMode = TVMode
    }

    /// Updates the track's artwork URL.
    /// - Parameter track: The track with the new artwork URL.
    public func updateTrack(track: Track) {
        queue.sync {
            self.artworkURL = track.artworkURL
        }
    }
}

extension Track: Hashable {
    public static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.trackID == rhs.trackID && lhs.name == rhs.name && lhs.position == rhs.position && lhs.TVMode == rhs.TVMode && lhs.artworkURL == rhs.artworkURL
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(trackID)
        hasher.combine(artworkURL)
        hasher.combine(name)
        hasher.combine(position)
        hasher.combine(TVMode)
    }
}

public extension Track {
    /// A formatted timestamp of the current playback position.
    var timestamp: String {
        formatTimestamp(playbackPosition)
    }

    /// A formatted timestamp of the remaining time of the track.
    var remainingTimestamp: String {
        formatTimestamp(duration - playbackPosition, negative: true)
    }

    /// Formats a given time interval into a timestamp.
    /// - Parameters:
    ///   - interval: The time interval to format.
    ///   - negative: A Boolean value indicating whether the timestamp should be negative.
    /// - Returns: A formatted string representing the time interval.
    private func formatTimestamp(_ interval: TimeInterval, negative: Bool = false) -> String {
        let totalSeconds = interval / 1000
        let hours = Int(totalSeconds / 3600)
        let minutes = Int((totalSeconds / 60).truncatingRemainder(dividingBy: 60))
        let seconds = Int(totalSeconds.truncatingRemainder(dividingBy: 60))
        let sign = negative ? "-" : ""

        return hours > 0 ? "\(sign)\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))" : "\(sign)\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
    }

    /// A static instance of `Track` representing an empty state.
    static let empty = Track(trackID: "", name: "")
}
