import Foundation

/// Track metadata at a point in time. Value type so that assigning a new Track
/// to `Room.track` is a value-write that fires Room's @Observable tracker with
/// fresh content, and every consumer reading `room.track.X` re-renders. Under
/// the prior `@Observable class` design, replacement (`room.track = newTrack`)
/// fired Room's observer but left subscribers to the discarded Track instance's
/// properties stuck on stale values — that's what made title/artist/artwork
/// linger after a track change on device. See [[observable-replace-vs-mutate]].
///
/// `playbackPosition` is the *parsed* position from the device response; the
/// UI-facing position lives on `Room` (`Room.playbackPosition`) so high-frequency
/// pulses don't invalidate every track-field consumer twice a second. Setters in
/// SonosService copy the parsed value into Room via
/// `room.updatePlaybackPosition(track.playbackPosition)`.
public struct Track: Identifiable, Hashable, Sendable {
    /// Stable identity for `Identifiable` conformance. Includes `position` so
    /// the same track at different queue indices is distinguishable.
    public var id: String { trackID + name + position.description }

    /// Coarser identity used to detect "is this a different song" — ignores
    /// position so a queue reorder of the same track doesn't look like a new
    /// song to consumers comparing `unique`.
    public var unique: String { trackID + name }

    /// True when the device reported no current track (no ID and no title).
    /// Distinct from `== .empty`: a radio source attaches station artwork to
    /// an otherwise-empty track (ads / idle station), which full equality
    /// treats as "not empty".
    public var isEmpty: Bool { trackID.isEmpty && name.isEmpty }

    public let trackID: String
    public var name: String
    public var song: String { metadata?.song ?? name }
    public var artist: String
    public var album: String

    public var artworkURL: URL? {
        if let downloadedArtworkURL { return downloadedArtworkURL }
        // Prefer the per-track art Sonos reports; fall back to the station logo
        // when the track has none (e.g. ads / spoken breaks, where the track is
        // otherwise empty — so this fallback runs before any empty-track check).
        if let sonosAlbumArtURL { return sonosAlbumArtURL }
        return radioStationArtworkURL
    }

    public var downloadedArtworkURL: URL?
    public var radioStationArtworkURL: URL?
    public var musicService: MusicService
    public var position: Int
    public var sonosAlbumArtURL: URL?
    public var metadata: Metadata?
    public var duration: TimeInterval

    /// Parsed playback position from the device response. UI should NOT read
    /// this directly — use `Room.playbackPosition` instead (which is updated
    /// by SonosService when a new Track arrives). Kept on the struct so the
    /// XML parser has somewhere to deposit the value without changing the
    /// parser's return shape.
    public var playbackPosition: TimeInterval

    public var timeRemaining: Duration {
        Duration.milliseconds(duration - playbackPosition)
    }

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
        self.playbackPosition = playbackPosition
        self.position = position
        self.sonosAlbumArtURL = sonosAlbumArtURL
        self.metadata = metadata
    }
}

public extension Track {
    /// Builds a display-only Track from an item the metadata socket reported.
    ///
    /// Carries only what the player needs to render immediately — title,
    /// artist, album, duration, art. The socket speaks the music service's
    /// *catalog* id namespace, not the transport `trackID` the position-info
    /// parser produces, so this is never the real track: it holds the screen
    /// during a skip until `updateTrackInformation` replaces it. Returns nil
    /// for an item with no title, which has nothing to show.
    init?(socketItem: SonosTrackInfo) {
        guard let name = socketItem.name, !name.isEmpty else { return nil }
        let artwork = socketItem.imageUrl
            ?? socketItem.images?.compactMap(\.url).first
        self.init(
            trackID: socketItem.id?.objectId ?? "",
            name: name,
            artist: socketItem.artist?.name ?? "",
            album: socketItem.album?.name ?? "",
            artworkURL: artwork.flatMap { URL(string: $0) },
            duration: TimeInterval(socketItem.durationMillis ?? 0)
        )
    }

    static let empty = Track(trackID: "", name: "")
    static let alarm = Track(trackID: "x-rincon-buzzer:0", name: "Alarm")
    static let tv = Track(trackID: "x-sonos-htastream", name: "TV")
}
