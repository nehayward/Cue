import Foundation

/// An observable class representing a track in a music service.
public struct SonosTrack: Identifiable, Sendable {
    /// The identifier for `Identifiable` conformance.
    public var id: String { trackID + name + position.description }
    
    /// The unique identifier of the track.
    public let trackID: String
    
    public let trackURI: String

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
    public var musicService: SonosMusicServiceType = .unknown

    /// The position of the track in a playlist or queue.
    public var position: Int
    
    /// The URL for the album art specific to Sonos service.
    public var sonosAlbumArtURL: URL?

    public var metadata: Metadata?

    /// The duration of the track, in seconds.
    public var duration: Duration

    /// The playback position of the track, thread-safe.
    public var elapsed: Duration

    public var timeRemaining: Duration {
        duration - elapsed
    }
    
    public var albumArtURI: String?

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
        trackURI: String,
        name: String = "",
        artist: String = "",
        album: String = "",
        artworkURL: URL? = nil,
        musicService: SonosMusicServiceType = .unknown,
        duration: Duration = .zero,
        playbackPosition: Duration = .zero,
        position: Int = 0,
        sonosAlbumArtURL: URL? = nil,
        metadata: Metadata? = nil,
        albumArtURI: String? = nil
    ) {
        self.elapsed = .zero
        self.trackID = trackID
        self.trackURI = trackURI
        self.name = name
        self.artist = artist
        self.album = album
        self.downloadedArtworkURL = artworkURL
        self.musicService = musicService
        self.duration = duration
        self.position = position
        self.sonosAlbumArtURL = sonosAlbumArtURL
        self.metadata = metadata
        self.albumArtURI = albumArtURI
    }
}

extension SonosTrack: Hashable {
    public static func == (lhs: SonosTrack, rhs: SonosTrack) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(position)
    }
}

public extension SonosTrack {
    /// A static instance of `Track` representing an empty state.
    static let empty = SonosTrack(trackID: "", trackURI: "", name: "")
    static let alarm = SonosTrack(trackID: "x-rincon-buzzer:0", trackURI: "", name: "Alarm")
}
