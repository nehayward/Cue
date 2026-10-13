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

    /// Whether the album can key the artwork cache: every song on an album
    /// shares its cover.
    public var albumKeysArtwork: Bool {
        !album.isEmpty
    }

    /// The artwork cache key the player and the lock screen share, so both
    /// name the same entry: album, else track name, else id, else the URL.
    public var playerArtworkCacheKey: String {
        let service = String(describing: musicService)
        if albumKeysArtwork { return "\(album).\(service).player" }
        if !name.isEmpty { return "\(name).\(service).player" }
        if !trackID.isEmpty { return trackID + ".player" }
        // Identity-less track (an idle radio player's resting track has no
        // album/name/trackID): key by the artwork URL. A bare ".player" key
        // was shared by every idle radio room, so each room's player showed
        // whichever station's art happened to be cached first.
        return (artworkURL?.absoluteString ?? "") + ".player"
    }

    public var downloadedArtworkURL: URL?
    public var radioStationArtworkURL: URL?
    public var musicService: MusicService
    public var position: Int
    public var sonosAlbumArtURL: URL?
    public var metadata: Metadata?
    public var duration: TimeInterval

    /// Shown on a skip press before the speaker has moved: built from the
    /// queue or the socket's next item, so it lacks the catalog metadata and
    /// full-size artwork the real track gets. Not identity — `trackID` and
    /// `unique` are the real song's, so favorites, queue highlights and caches
    /// see the right song — which is why the poll's same-song shortcuts check
    /// it: a preview still needs the lookup.
    public var isSkipPreview = false

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

extension Track {
    /// Same-album carry: a track on the album already on screen takes its
    /// full-size cover URL, so the artwork view never drops to the speaker's
    /// proxy art (or to nothing) while this track's own lookup runs. Spotify
    /// sends only `dc:creator`, so without it the URL changed twice on every
    /// track change within an album, which showed as a flash.
    mutating func inheritAlbumArtwork(from shown: Track) {
        guard downloadedArtworkURL == nil,
              albumKeysArtwork,
              album == shown.album,
              let artworkURL = shown.downloadedArtworkURL else { return }
        downloadedArtworkURL = artworkURL
    }
}

public extension Track {
    static let empty = Track(trackID: "", name: "")
    static let alarm = Track(trackID: "x-rincon-buzzer:0", name: "Alarm")
    static let tv = Track(trackID: "x-sonos-htastream", name: "TV")

    /// Line-in from the speaker `uri` names (`x-rincon-stream:<its id>`). The
    /// URI is the track's ID, so a switch to another speaker's input is a new
    /// track.
    static func lineIn(uri: String) -> Track {
        Track(trackID: uri, name: "Line In")
    }

    /// The speaker whose line-in this is, nil for anything else. A speaker
    /// playing its own input reports an input number after the id
    /// (`x-rincon-stream:RINCON_…01400:0`), so the id ends at the first colon.
    var lineInSourceID: String? {
        let prefix = "x-rincon-stream:"
        guard trackID.hasPrefix(prefix),
              let id = trackID.dropFirst(prefix.count).split(separator: ":").first else { return nil }
        return String(id)
    }
}
