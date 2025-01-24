import Foundation

/// An observable class representing a track in a music service.
@Observable
public final class Track: Identifiable, Sendable {    
    /// The identifier for `Identifiable` conformance.
    public var id: String { trackID + name + position.description }

    private let queue = DispatchQueue(label: "Track.\(UUID().uuidString)")

    @ObservationIgnored private var _playbackPosition: TimeInterval = .zero

    /// The unique identifier of the track.
    public let trackID: String

    /// The name of the track.
    public var name: String

    public var song: String { metadata?.song ?? name }

    /// The artist of the track.
    public var artist: String

    /// The album of the track.
    public var album: String

    /// The URL for the track's artwork.
    public var artworkURL: URL? {
        if trackID.isEmpty, name.isEmpty { return nil }
        if let downloadedArtworkURL {
            return downloadedArtworkURL
        }
        return sonosAlbumArtURL
    }

    /// The URL for the track's artwork.
    public var downloadedArtworkURL: URL?

    /// The music service associated with the track.
    public var musicService: MusicService

    /// The position of the track in a playlist or queue.
    public var position: Int
    
    /// The URL for the album art specific to Sonos service.
    public var sonosAlbumArtURL: URL?

    public var metadata: Metadata?

    /// The duration of the track, in seconds.
    public var duration: TimeInterval

    /// The playback position of the track, thread-safe.
    public var playbackPosition: TimeInterval {
        get { queue.sync { _playbackPosition } }
        set { queue.sync { _playbackPosition = newValue } }
    }

    public var timeRemaining: Duration {
        Duration.milliseconds(duration - playbackPosition)
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
        metadata: Metadata? = nil
    ) {
        self.trackID = trackID
        self.name = name
        self.artist = artist
        self.album = album
        self.downloadedArtworkURL = artworkURL
        self.musicService = musicService
        self.duration = duration
        self._playbackPosition = playbackPosition
        self.position = position
        self.sonosAlbumArtURL = sonosAlbumArtURL
        self.metadata = metadata
    }
}

extension Track: Hashable {
    public static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.trackID == rhs.trackID &&
        lhs.name == rhs.name &&
        lhs.position == rhs.position
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(position)
    }
}

public extension Track {
    /// A static instance of `Track` representing an empty state.
    static let empty = Track(trackID: "", name: "")
    static let alarm = Track(trackID: "x-rincon-buzzer:0", name: "Alarm")
}
