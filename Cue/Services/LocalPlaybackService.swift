import AVFoundation
import Defaults
import Foundation
import MusicKit
import Observation
import SonosKit
import UIKit

/// Plays full songs on this device instead of on a Sonos group. Keeps one
/// queue of `PlayableContent` — Apple Music and Plex tracks can mix freely.
///
/// A single player for both services is impossible (full Apple Music audio is
/// DRM'd into Apple's players, which can't play a Plex URL), so the queue is
/// armed in **runs**: each contiguous same-service stretch is handed to its
/// native player in one go — `ApplicationMusicPlayer` for Apple, `AVQueuePlayer`
/// for Plex streams — so within a run the system player advances tracks itself
/// (gapless, and immune to the app napping in the background). This service
/// only steps in at a service boundary, arming the next run when one ends.
///
/// - Apple playback runs in the system music service (not our audio session),
///   so it doesn't fight the preview player or the hardware-volume bridge —
///   but it needs an active Apple Music subscription; `play` throws without
///   one and callers surface that through `AlertService`.
/// - Plex and Subsonic tracks stream their full file (`previewURL` is the
///   whole track served from the user's own server).
/// - Radio plays too, one station at a time: a TuneIn station is a live
///   stream resolved from its id and handed to `AVQueuePlayer`; an Apple
///   Music station is a MusicKit `Station` the Apple player runs itself.
///   A station is always a run of one — nothing follows a live stream.
///
/// The displayed metadata never needs a fetch — `nowPlaying` is the same
/// `PlayableContent` the search returned. The only network hop is resolving
/// Apple ids into `Song` values, because MusicKit refuses to queue anything
/// less than a real catalog `Song`.
///
/// The queue outlives the process: it is written to disk as it changes and
/// the position a few times a minute, and the next launch loads both back
/// paused — the track that was playing, at the point it had reached — so a
/// kill from the app switcher, or the system reclaiming the app, doesn't
/// throw away what was queued. Nothing is armed until Play; the first arm
/// then seeks to the saved spot. The route moving to a speaker parks the
/// queue the same way (`park()`): the speaker takes over, and the phone's
/// queue waits where it was rather than being thrown away.
@MainActor
@Observable
final class LocalPlaybackService {
    static let shared = LocalPlaybackService()

    private init() {
        restoreSavedQueue()
        // The position is what changes most and is written least: make sure
        // the latest one is on disk before the app can be killed quietly.
        // `willTerminate` doesn't come for a kill from the switcher while
        // suspended, which is why the poll also writes every few seconds.
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification] {
            observers.append(Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    self?.flushSavedState()
                }
            })
        }
    }

    enum LocalPlaybackError: LocalizedError {
        case songNotFound
        case stationNotFound
        case nothingPlayable

        var errorDescription: String? {
            switch self {
            case .songNotFound:
                "Couldn't find this song on Apple Music"
            case .stationNotFound:
                "Couldn't find a stream for this station"
            case .nothingPlayable:
                "Nothing here can play on this device"
            }
        }
    }

    private enum Backend {
        case appleMusic
        /// An Apple Music station in `ApplicationMusicPlayer` — the same
        /// player as `appleMusic`, with no entries to follow through.
        case appleStation
        case stream
    }

    /// What happens when the queue runs out, or a track ends — the same three
    /// modes a Sonos queue has.
    enum RepeatMode: String, CaseIterable, Codable {
        case off
        case all
        case one

        /// The next mode a single repeat button cycles to.
        var next: RepeatMode {
            switch self {
            case .off: .all
            case .all: .one
            case .one: .off
            }
        }

        var title: String {
            switch self {
            case .off: "Repeat Off"
            case .all: "Repeat All"
            case .one: "Repeat One"
            }
        }

        var systemImage: String {
            switch self {
            case .off, .all: "repeat"
            case .one: "repeat.1"
            }
        }
    }

    // MARK: - Observable queue + now-playing state

    /// The local queue, in play order. Mixed services are fine — playback is
    /// armed per same-service run.
    private(set) var queue: [PlayableContent] = [] {
        didSet {
            cacheNeedsRefresh()
            queueNeedsSave()
        }
    }
    private(set) var currentIndex: Int = 0 {
        didSet {
            if oldValue != currentIndex {
                cacheNeedsRefresh()
                savePosition()
            }
        }
    }
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var progress: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    var nowPlaying: PlayableContent? { queue[safe: currentIndex] }

    /// Whether a live station is what's playing: no skipping, no queue
    /// behind it, nothing to scrub.
    var isPlayingStation: Bool {
        nowPlaying.map(isStation) ?? false
    }

    /// What's on air on the current station: the song, who's playing it, and
    /// its artwork when a lookup found some. Nil for a track, and for a
    /// station that hasn't said yet.
    private(set) var liveMetadata: LiveStationMetadata?

    /// The item the player draws. A track is itself; a station becomes the
    /// song on air, with the station's name where an album's would go — the
    /// same shape `LargePlayerView` gives a Sonos radio stream.
    var nowPlayingDisplay: PlayableContent? {
        guard let item = nowPlaying else { return nil }
        guard isStation(item), let live = liveMetadata else { return item }
        // The image cache is keyed by `imageKey`, which falls back to the
        // id when there's no album. The id has to change with the artwork:
        // the station's logo is shown under the station's id until a song's
        // cover is found, and the cover then needs a key of its own —
        // otherwise the cache answers the new URL with the logo it already
        // holds under the old key.
        let identity = live.artworkURL == nil
            ? item.content.id
            : "\(item.content.id)#\(live.song)#\(live.artist ?? "")"
        return PlayableContent(
            title: live.song,
            subtitle: live.artist ?? item.title,
            thumbnail: live.artworkURL ?? item.thumbnail,
            artwork: live.artworkURL ?? item.artwork,
            content: MediaContent(service: item.content.service, id: identity, type: item.content.type, location: item.content.location),
            metadata: .init(artist: live.artist, radioStation: true)
        )
    }
    /// What this queue was played from — the album, playlist, artist or
    /// folder the Play came from, or the parent of the row that was tapped.
    /// The device's answer to the container line the Sonos player reads off
    /// the speaker, and a way back into it: the player names it above the
    /// title and a tap opens it.
    ///
    /// Queue-level, like the speaker's own: it is set by the Play that
    /// replaced the queue and survives tracks being added behind it, so a
    /// row queued from elsewhere still shows the origin of the run it landed
    /// in. Nil when the queue came from a bare list of tracks — a search
    /// result, a speaker hand-off — which have no origin to name.
    private(set) var source: PlayableContent? {
        didSet { saveSource() }
    }

    var upNext: [PlayableContent] { Array(queue.dropFirst(currentIndex + 1)) }
    var isActive: Bool { !queue.isEmpty }
    /// Whether a skip forward has somewhere to go: another track, or the top
    /// of the queue again when it repeats.
    var hasNext: Bool { currentIndex + 1 < queue.count || (repeatMode == .all && !queue.isEmpty) }

    /// How the queue loops. Repeat One shortens the armed run to the current
    /// track, so the native player hands back at the end of each one instead
    /// of sailing on to the next.
    private(set) var repeatMode: RepeatMode = .off
    /// When the sleep timer will pause playback, if one is running. Nil for
    /// none and for the end-of-track kind, which has no fixed time.
    private(set) var sleepTimerEndDate: Date?
    /// Pause when the current track ends rather than at a time.
    private(set) var sleepsAtEndOfTrack = false
    /// What the armed player is decoding — lossless, Atmos, bit depth and
    /// sample rate as far as the backend will say. Apple's player reports
    /// the variant it is actually playing; a stream's is read off its asset.
    private(set) var audioQuality: SonosTrackQuality?

    // MARK: - Armed-run state

    @ObservationIgnored private var backend: Backend?
    /// Inclusive queue range the armed player currently owns. Empty (`end <
    /// start`) when nothing is armed.
    @ObservationIgnored private var runEnd = -1
    @ObservationIgnored private let musicPlayer = ApplicationMusicPlayer.shared
    /// The armed Apple run: player-entry offset → (queue index, resolved song).
    /// Rows that failed to resolve are absent, which is why this maps offsets
    /// to queue indices instead of assuming they line up.
    @ObservationIgnored private var appleRun: [(queueIndex: Int, song: Song)] = []
    /// Set once the Apple player has actually played, so a `.stopped` read
    /// means "run ended", not "still warming up".
    @ObservationIgnored private var appleWasPlaying = false
    @ObservationIgnored private var streamPlayer: AVQueuePlayer?
    /// Reads ICY stream titles off a station's player item.
    @ObservationIgnored private var streamMetadataListener: StreamMetadataListener?
    /// Polls TuneIn for what the current station is playing.
    @ObservationIgnored private var stationMetadataTask: Task<Void, Never>?
    /// The stream player's own output level, 0...1 — `DeviceVolume` drives
    /// it where the device volume can't be set. Carried onto each new run.
    @ObservationIgnored var streamVolume: Float = 1 {
        didSet { applyStreamVolume() }
    }
    /// Live Transcription's ear on the station playing here — see
    /// `tapStationAudio(_:)`. Carried onto each new station item.
    @ObservationIgnored private var stationAudioTap: (@Sendable (AVAudioPCMBuffer, CMTime) -> Void)?
    /// The station item carrying the tap. It plays with the player at full
    /// level and `streamVolume` applied by the tap, which hears the mix after
    /// the player's volume and would otherwise go deaf with it turned down.
    @ObservationIgnored private weak var tappedItem: AVPlayerItem?
    @ObservationIgnored private let stationTapGain = TapGain()
    /// The armed stream run: player item → queue index.
    @ObservationIgnored private var streamRun: [ObjectIdentifier: Int] = [:]
    /// Resolved Apple `Song`s by catalog id, so replaying or skipping back to
    /// a track doesn't re-fetch it. Loaded from (and saved to) disk, which is
    /// what lets a previously seen track arm with no network — so songs the
    /// Music app has downloaded can start in airplane mode.
    @ObservationIgnored private var songCache: [String: Song] = SongDiskCache.load()
    @ObservationIgnored private var poller: Timer?
    /// Bumped on every re-arm so a stale async resolve can't start playback
    /// for a run the user has already skipped away from.
    @ObservationIgnored private var playToken = 0
    /// The Lock Screen card for the stream backend. Apple Music's player
    /// publishes its own.
    @ObservationIgnored private lazy var nowPlayingCard = LocalNowPlayingPresenter(player: self)
    /// True while the stream backend is armed — the Sonos Lock Screen mirror
    /// stands down for it, since iOS has one Now Playing app at a time.
    private(set) var isPlayingLocalStream = false
    /// Debounces the playback cache's look at the queue: page appends and
    /// polled index changes come in bursts.
    @ObservationIgnored private var cacheRefreshTask: Task<Void, Never>?
    /// Counts down a timed sleep timer.
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    /// Reads a stream item's format off its asset; one in flight at a time.
    @ObservationIgnored private var audioQualityTask: Task<Void, Never>?
    /// The stream item `audioQuality` describes, so the poll only reads a
    /// format when the item changes.
    @ObservationIgnored private var audioQualityItem: ObjectIdentifier?
    /// The Apple queue entry whose variant has been read, likewise.
    @ObservationIgnored private var audioVariantEntryID: String?
    /// Seconds into the current track to pick up from once it is armed —
    /// set by a restore, used by the first arm of that same track, and
    /// dropped by anything that arms a different one.
    @ObservationIgnored private var resumePosition: TimeInterval?
    /// Debounces the queue's write to disk, for the same bursts as the cache.
    @ObservationIgnored private var queueSaveTask: Task<Void, Never>?
    /// True from a queue change until it has been written.
    @ObservationIgnored private var queueNeedsWrite = false
    /// The progress last written, so the poll only writes every few seconds
    /// of playback rather than every tick.
    @ObservationIgnored private var savedProgress: TimeInterval = 0
    /// True while the saved queue is being loaded back, so the loads don't
    /// write themselves straight back out.
    @ObservationIgnored private var isRestoring = false
    @ObservationIgnored private var observers: [Task<Void, Never>] = []

    /// Whether the queue can take this item: Apple tracks (catalog or library),
    /// Plex or Subsonic tracks that carry their stream URL, and TuneIn or
    /// Apple Music stations.
    func canPlayLocally(_ item: PlayableContent) -> Bool {
        backendKind(for: item) != nil
    }

    /// A live station: a run of one, with no duration and nothing after it.
    private func isStation(_ item: PlayableContent) -> Bool {
        item.content.type.isRadio
    }

    private func backendKind(for item: PlayableContent) -> Backend? {
        switch item.content.service {
        case .apple where [.track, .libraryTrack].contains(item.content.type):
            .appleMusic
        case .apple where [.radio, .liveRadio].contains(item.content.type):
            .appleStation
        // A TuneIn station: the stream URL is resolved from the station id
        // when the run is armed (see `streamURL(for:)`).
        case .tuneIn where item.content.type == .radio:
            .stream
        case .plex where item.content.type == .track
            && (item.previewURL != nil || DownloadManager.shared.isDownloaded(item)):
            .stream
        // Subsonic's `previewURL` is the whole track off the user's own server
        // (`/rest/stream`), exactly like Plex's — so the same `AVQueuePlayer`
        // path plays it, and the same download manager keeps a copy.
        case .subsonic where item.content.type == .track
            && (item.previewURL != nil || DownloadManager.shared.isDownloaded(item)):
            .stream
        // A file in the user's folder: `previewURL` is the file itself, and
        // only set once an iCloud file has actually downloaded.
        case .files where item.content.type == .track && item.previewURL != nil:
            .stream
        default:
            nil
        }
    }

    /// Whether this is a container — album or playlist — whose tracks the local
    /// queue can take. They get fetched first, see `containerTracks(for:)`.
    func canPlayContainerLocally(_ item: PlayableContent) -> Bool {
        // An album or artist from the on-device library: its songs are
        // already here, whatever the service.
        if OnDeviceLibrary.isContainer(item) { return true }
        return switch (item.content.type, item.content.service) {
        case (.album, .apple), (.libraryAlbum, .apple), (.album, .plex):
            true
        case (.playlist, .apple), (.libraryPlaylist, .apple), (.playlist, .plex):
            true
        case (.album, .files), (.artist, .files), (.playlist, .files):
            true
        // Subsonic containers expand the way they do for Sonos: the same
        // tracks, with the same stream URLs, so the local queue and the
        // download manager can take an album whole.
        case (.album, .subsonic), (.artist, .subsonic), (.playlist, .subsonic):
            true
        default:
            false
        }
    }

    /// One page of a container's tracks, fetched the same way its detail
    /// screen does. Sources that answer in a single shot return everything at
    /// offset 0 and nothing after, so callers can page uniformly.
    func containerTracks(for container: PlayableContent, offset: Int = 0) async -> [PlayableContent] {
        // The on-device library's containers expand from what's here, not
        // a server — that's the point of them.
        if let onDevice = OnDeviceLibrary.tracks(inContainer: container) {
            return offset == 0 ? onDevice : []
        }
        switch (container.content.type, container.content.service) {
        case (.album, .apple):
            guard offset == 0 else { return [] }
            guard let full: Album = try? await MusicSearchService.shared.lookup(id: container.content.id),
                  let tracks = full.tracks else { return [] }
            return await MusicSearchService.shared.tracksToPlayableWithPreviews(tracks)
        case (.libraryAlbum, .apple):
            guard offset == 0 else { return [] }
            return await AppleMusicBrowseService.shared.albumLookup(id: container.content.id)
        case (.album, .plex):
            guard offset == 0 else { return [] }
            return await MusicSearchService.shared.lookupPlexAlbumSongs(id: container.content.id)
        case (.playlist, .apple):
            // `getTracksFromPlaylist`, not `lookup(id:)` — the plain lookup can
            // come back with `tracks` still nil, which is why the detail screen
            // uses this one. Mirroring it keeps the two in step.
            guard offset == 0 else { return [] }
            guard let tracks = try? await MusicSearchService.shared.getTracksFromPlaylist(id: container.content.id) else { return [] }
            return await MusicSearchService.shared.tracksToPlayableWithPreviews(tracks)
        case (.libraryPlaylist, .apple):
            // Paged — a playlist can run well past what one request returns.
            return await AppleMusicBrowseService.shared
                .tracksForUserPlaylists(id: container.content.id, offset: offset).0
        case (.playlist, .plex):
            // Paged too: `X-Plex-Container-Size` caps each response at 200.
            return await MusicSearchService.shared
                .lookupPlexPlaylists(id: container.content.id, offset: offset).1
        case (.album, .files):
            guard offset == 0 else { return [] }
            return FilesLibraryService.shared.albumTracks(albumID: container.content.id)
        case (.artist, .files):
            guard offset == 0 else { return [] }
            return FilesLibraryService.shared.artistTracks(artistID: container.content.id)
        case (.playlist, .files):
            // An .m3u in the folder, or the All Songs container behind the
            // Songs list's Play All.
            guard offset == 0 else { return [] }
            return FilesLibraryService.shared.playlistTracks(playlistID: container.content.id)
        case (.album, .subsonic), (.artist, .subsonic), (.playlist, .subsonic):
            guard offset == 0 else { return [] }
            return await MusicSearchService.shared.containerTracks(for: container)
        default:
            return []
        }
    }

    /// Appends everything after the page already queued. Runs detached from the
    /// caller so playback starts on the first page — draining a 1600-track
    /// playlist up front meant nine sequential requests before the first note,
    /// which read as the Play button doing nothing.
    private func appendRemainder(of container: PlayableContent, from start: Int, shuffle: Bool = false) async {
        guard start > 0 else { return }
        var offset = start
        // Bounded: a source that quietly ignored `offset` would otherwise
        // append its first page forever.
        for _ in 0 ..< 200 {
            let page = await containerTracks(for: container, offset: offset)
            guard !page.isEmpty else { return }
            offset += page.count
            try? await addToQueue(shuffle ? page.shuffled() : page)
        }
    }

    /// Replaces the queue with `items` and starts at `index` (an index into
    /// `items` — unplayable rows are dropped, and the start follows the item).
    ///
    /// `position` starts the track that many seconds in — a hand-off from a
    /// speaker picks up where it was. It is applied before the player starts
    /// rather than as a seek after: a seek landing while the Apple player is
    /// still preparing its entry is dropped, and the track started from the
    /// top.
    func play(_ items: [PlayableContent], startingAt index: Int = 0, from position: TimeInterval? = nil) async throws {
        let playable = items.filter { canPlayLocally($0) }
        guard !playable.isEmpty else { throw LocalPlaybackError.nothingPlayable }
        // A new queue, so the old origin is gone. `enqueue` names the new one
        // after this returns; a bare list of tracks has none.
        source = nil
        queue = playable
        let start = items[safe: index].flatMap { playable.firstIndex(of: $0) } ?? 0
        // A new queue, so a restored position belongs to nothing in it.
        resumePosition = nil
        try await arm(at: start, from: position)
    }

    /// Inserts `items` right after the current track, in order. Starts
    /// playing if the queue was empty.
    func playNext(_ items: [PlayableContent]) async throws {
        let playable = items.filter { canPlayLocally($0) }
        guard !playable.isEmpty else { throw LocalPlaybackError.nothingPlayable }
        guard isActive else { return try await play(playable) }
        // The armed player owns everything up to `runEnd` and would sail past
        // the insertion straight into its old next track — cut it off after
        // the current one so the run-end advance picks the insert up instead.
        if runEnd > currentIndex {
            truncateArmedRunAfterCurrent()
        }
        queue.insert(contentsOf: playable, at: min(currentIndex + 1, queue.count))
    }

    func playNext(_ item: PlayableContent) async throws {
        try await playNext([item])
    }

    /// Appends `items` to the end of the queue (they play when the armed run
    /// ends and the advance reaches them). Starts playing if the queue was
    /// empty.
    func addToQueue(_ items: [PlayableContent]) async throws {
        let playable = items.filter { canPlayLocally($0) }
        guard !playable.isEmpty else { throw LocalPlaybackError.nothingPlayable }
        guard isActive else { return try await play(playable) }
        queue.append(contentsOf: playable)
    }

    func addToQueue(_ item: PlayableContent) async throws {
        try await addToQueue([item])
    }

    /// One entry point for "play this here, at this queue position" — used by
    /// the share extension's Device hand-off and by the play sheet, so the
    /// position mapping can't drift between them. Albums are expanded to their
    /// tracks first. Throws `.nothingPlayable` when the local queue can't take
    /// the content at all, which is the signal callers fall back to a Sonos
    /// group on.
    func enqueue(_ content: PlayableContent, at position: QueuePosition, shuffle: Bool = false, from origin: PlayableContent? = nil) async throws {
        try await enqueue([content], at: position, shuffle: shuffle, from: origin)
    }

    /// The same, for a whole run at once — the artist screen's popular tracks
    /// and discography arrive as a list. Order is preserved and containers are
    /// expanded in place, so a discography lands album by album the way it
    /// would on a speaker. Anything with no local backend is skipped rather
    /// than failing the lot; only an empty result throws.
    ///
    /// `shuffle` shuffles within each page as it arrives rather than across the
    /// whole container: a true global shuffle needs every page in hand first,
    /// which is exactly the wait that starting on page one avoids. At Plex's
    /// 200 tracks per page that reads as shuffled.
    ///
    /// `origin` is where the Play came from, for `source` to name — the
    /// playlist a tapped row belongs to, say, which the row itself doesn't
    /// carry. A single container needs none: it is its own origin.
    func enqueue(_ contents: [PlayableContent], at position: QueuePosition, shuffle: Bool = false, from origin: PlayableContent? = nil) async throws {
        let wasEmpty = !isActive
        var items: [PlayableContent] = []
        /// Containers whose first page is in `items`; the rest follows once
        /// playback is underway.
        var containers: [(content: PlayableContent, loaded: Int)] = []
        for content in contents {
            if canPlayLocally(content) {
                items.append(content)
            } else if canPlayContainerLocally(content) {
                let page = await containerTracks(for: content, offset: 0)
                items += shuffle ? page.shuffled() : page
                containers.append((content, page.count))
            }
        }
        guard !items.isEmpty else { throw LocalPlaybackError.nothingPlayable }

        switch position {
        case .now, .replace: try await play(items)
        case .next, .front: try await playNext(items)
        case .end: try await addToQueue(items)
        }

        // Only the Play that made the queue names its origin: adding behind
        // an existing queue leaves the run it joins as what it was. A lone
        // container stands in for itself when the caller named nothing —
        // that is the playlist or album that was tapped.
        if [.now, .replace].contains(position) || wasEmpty {
            source = origin ?? (contents.count == 1 ? contents.first.flatMap { canPlayContainerLocally($0) ? $0 : nil } : nil)
        }

        // Playing already, so the tail can arrive behind it.
        guard !containers.isEmpty else { return }
        Task {
            for container in containers {
                await appendRemainder(of: container.content, from: container.loaded, shuffle: shuffle)
            }
        }
    }

    /// Whether `enqueue` has any chance with this content — the cheap check the
    /// UI uses to decide whether to offer Device at all.
    func canPlayAnywhereLocally(_ content: PlayableContent) -> Bool {
        canPlayLocally(content) || canPlayContainerLocally(content)
    }

    /// Scrubs within the current track. Whichever player owns the armed run
    /// takes it — the two backends share no seek API, and neither is armed
    /// when nothing is playing.
    func seek(to seconds: TimeInterval) {
        let seconds = Self.finite(seconds, else: 0)
        progress = seconds
        savePosition()
        switch backend {
        case .appleMusic:
            musicPlayer.playbackTime = seconds
        case .stream:
            streamPlayer?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
            nowPlayingCard.noteSeek(elapsed: seconds)
        case .appleStation:
            // A station has nowhere to seek to.
            break
        case nil:
            // Nothing armed — a restored queue, or one parked by an
            // end-of-track sleep timer. Play arms the track and picks up
            // from here rather than from where it was saved.
            resumePosition = seconds
        }
    }

    /// Jumps to `index` in the queue (e.g. a tap in the Up Next list).
    func play(at index: Int) {
        guard queue.indices.contains(index) else { return }
        Task { try? await arm(at: index) }
    }

    // MARK: - Transport

    func togglePlayback() {
        switch backend {
        case .appleMusic, .appleStation:
            if musicPlayer.state.playbackStatus == .playing {
                musicPlayer.pause()
            } else {
                Task { try? await musicPlayer.play() }
            }
        case .stream:
            guard let streamPlayer else { return }
            if streamPlayer.timeControlStatus == .paused {
                streamPlayer.play()
            } else {
                streamPlayer.pause()
            }
        case nil:
            // Queue loaded but nothing armed (e.g. a failed track) — retry it.
            Task { try? await arm(at: currentIndex) }
        }
    }

    /// Pauses whichever player is armed. Unlike `togglePlayback` this doesn't
    /// read the player's state first — right after `play` the Apple player
    /// can still report itself as not playing, and a toggle there would
    /// start it a second time instead of stopping it.
    func pause() {
        switch backend {
        case .appleMusic, .appleStation:
            musicPlayer.pause()
        case .stream:
            streamPlayer?.pause()
        case nil:
            break
        }
    }

    func setRepeatMode(_ mode: RepeatMode) {
        guard mode != repeatMode else { return }
        repeatMode = mode
        savePosition()
        // The armed run would carry straight past the current track; end it
        // there so the run-end hook can play it again. Leaving Repeat One
        // needs nothing: the next arm reads the mode and takes the whole run.
        if mode == .one, runEnd > currentIndex {
            truncateArmedRunAfterCurrent()
        }
    }

    /// Reorders what follows the current track at random. The current track
    /// keeps playing; the run is cut off after it so the new order takes
    /// effect at the next track boundary.
    func shuffleUpNext() {
        let start = currentIndex + 1
        guard start + 1 < queue.count else { return }
        if runEnd > currentIndex {
            truncateArmedRunAfterCurrent()
        }
        queue[start...].shuffle()
    }

    /// Pauses `duration` from now. Replaces any timer already running,
    /// including an end-of-track one.
    func sleepTimer(_ duration: Duration) {
        cancelSleepTimer()
        let seconds = TimeInterval(duration.components.seconds)
        sleepTimerEndDate = Date.now.addingTimeInterval(seconds)
        sleepTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            self.pause()
            self.sleepTimerEndDate = nil
        }
    }

    /// Pauses when the current track ends. The armed run is cut off after
    /// it, so the native player hands back instead of starting the next one;
    /// `advancePastRun` then parks on what would have played.
    func sleepAtEndOfTrack() {
        cancelSleepTimer()
        sleepsAtEndOfTrack = true
        if runEnd > currentIndex {
            truncateArmedRunAfterCurrent()
        }
    }

    func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimerEndDate = nil
        sleepsAtEndOfTrack = false
    }

    func next() {
        let target = currentIndex + 1
        guard target < queue.count else {
            if repeatMode == .all, !queue.isEmpty {
                Task { try? await arm(at: 0) }
            } else {
                stop()
            }
            return
        }
        // Inside the armed run the native skip is instant (and keeps the run's
        // gapless chain); past its end we arm the next run ourselves.
        if target <= runEnd, let backend {
            switch backend {
            case .appleMusic:
                Task { try? await musicPlayer.skipToNextEntry() }
            case .stream:
                streamPlayer?.advanceToNextItem()
            case .appleStation:
                // A station is its own run, so `target` is never inside it.
                Task { try? await arm(at: target) }
            }
        } else {
            Task { try? await arm(at: target) }
        }
    }

    func previous() {
        // First tap restarts the track, a quick second tap goes back — the
        // same rule every player uses.
        if progress > 3 || currentIndex == 0 {
            restartCurrent()
        } else {
            Task { try? await arm(at: currentIndex - 1) }
        }
    }

    func stop() {
        poller?.invalidate()
        poller = nil
        cancelSleepTimer()
        teardownRun()
        resumePosition = nil
        queue = []
        source = nil
        currentIndex = 0
        isPlaying = false
        isLoading = false
        progress = 0
        duration = 0
    }

    /// Takes the player down but keeps the queue: nothing armed, paused on
    /// the current track with the scrubber where it was, the same state a
    /// relaunch restores into. For the route moving to a speaker — the
    /// speaker takes over, and the phone's queue waits here for the route
    /// to come back (or for the next Play on this device), where `stop()`
    /// would have thrown it away. Play arms the track again and picks up
    /// from this spot, via `resumePosition`.
    func park() {
        guard isActive else { return }
        poller?.invalidate()
        poller = nil
        cancelSleepTimer()
        // Read before the teardown, which is what the poll's last tick left.
        let position = progress
        teardownRun()
        isPlaying = false
        isLoading = false
        // Under a couple of seconds is the start of the track, the same
        // cutoff a restore and a route switch use.
        resumePosition = position > 2 ? position : nil
        savePosition()
    }

    /// Arms the current track again and plays it, from the parked spot when
    /// there is one — the undo of `park()`, for a hand-off the speaker
    /// refused. `play(_:)` would replace the queue; this keeps it.
    func resumeCurrent() async throws {
        guard isActive else { return }
        try await arm(at: currentIndex)
    }

    /// Arms `index` and plays it from `seconds` in — for the route coming
    /// back to a queue parked here, at the track and spot the speaker had
    /// reached meanwhile. The queue is kept, played tracks included. The
    /// position goes in with the arm, so the player is pointed there before
    /// its first note (see `play(_:startingAt:from:)`).
    func resume(at index: Int, from seconds: TimeInterval) async throws {
        guard queue.indices.contains(index) else { return }
        // Same start-of-track cutoff as a restore.
        try await arm(at: index, from: seconds > 2 ? seconds : nil)
    }

    /// The length the catalog gave the queue row, or zero when it gave none.
    /// Every service that streams here — Plex, Subsonic, Files — parses one
    /// into `metadata.duration`; it fills in for what the player hasn't
    /// reported yet, or can't. A station stays at zero: a live stream has
    /// no length, and the scrubber hides on zero.
    private func catalogDuration(at index: Int) -> TimeInterval {
        guard let item = queue[safe: index], !isStation(item),
              let duration = item.metadata?.duration else { return 0 }
        return TimeInterval(duration.components.seconds)
            + TimeInterval(duration.components.attoseconds) / 1e18
    }

    // MARK: - Arming runs

    /// The last index of the contiguous same-backend run starting at `index`.
    /// A station never joins a run: a live stream has no end for the player
    /// to advance past, so it plays alone and the next item waits for a skip.
    private func runEnd(from index: Int) -> Int {
        guard let kind = backendKind(for: queue[index]), !isStation(queue[index]) else { return index }
        var end = index
        while end + 1 < queue.count,
              backendKind(for: queue[end + 1]) == kind,
              !isStation(queue[end + 1]) {
            end += 1
        }
        return end
    }

    /// Hands the run starting at `index` to its native player and starts it.
    ///
    /// `position` starts the track that many seconds in. Without it, the
    /// saved position is for the track that was current when the app last
    /// ran: this arm takes it if that is the track, and any other arm drops
    /// it, so a tap on another row can't land partway into it.
    private func arm(at index: Int, from position: TimeInterval? = nil) async throws {
        playToken += 1
        let token = playToken
        teardownRun()
        guard queue.indices.contains(index) else {
            stop()
            return
        }
        let resume = position ?? (index == currentIndex ? resumePosition : nil)
        resumePosition = nil
        currentIndex = index
        progress = 0
        // The catalog's length while the player loads: the scrubber keeps
        // its shape instead of dropping out until the first poll.
        duration = catalogDuration(at: index)
        // A restored queue arms from Play rather than `play(_:)`, which is
        // where the poll used to start.
        startPolling()
        // A run of one when the track has to hand back at its end: to play
        // again, or to pause there.
        let end = (repeatMode == .one || sleepsAtEndOfTrack) ? index : runEnd(from: index)

        switch backendKind(for: queue[index]) {
        case .stream:
            try await armStream(index: index, end: end, token: token, resume: resume)
        case .appleMusic:
            try await armApple(index: index, end: end, token: token, resume: resume)
        case .appleStation:
            try await armAppleStation(index: index, token: token)
        case nil:
            // Shouldn't happen — the queue only takes playable items.
            advancePastRun(endingAt: index)
        }
        // Pick up partway in. Only when this arm still owns playback and
        // started the track it was asked to — the resolve can skip a row that
        // failed, and a skip meanwhile moves on. The player was pointed there
        // before it started; this is the fallback for one that ignored it,
        // and otherwise just shows the position rather than rewinding the
        // moment already played.
        if let resume, playToken == token, backend != nil, currentIndex == index {
            if playerTime < resume - 1 {
                seek(to: resume)
            } else {
                progress = max(playerTime, resume)
                savePosition()
            }
        }
    }

    /// Where the armed player is in its track, straight from the player.
    private var playerTime: TimeInterval {
        switch backend {
        case .appleMusic, .appleStation:
            return musicPlayer.playbackTime
        case .stream:
            let seconds = streamPlayer?.currentTime().seconds ?? 0
            return seconds.isFinite ? seconds : 0
        case nil:
            return 0
        }
    }

    /// Moves on to whatever follows the armed run — or plays it again under
    /// Repeat One, wraps to the top under Repeat All, parks for an
    /// end-of-track sleep timer, and otherwise stops at the queue's end.
    private func advancePastRun(endingAt end: Int) {
        if sleepsAtEndOfTrack {
            sleepsAtEndOfTrack = false
            // Nothing armed, and the queue kept: Play picks up from what
            // would have played next, the way a paused speaker does.
            let next = repeatMode == .one ? end : end + 1
            if next < queue.count {
                currentIndex = next
            } else if repeatMode == .all {
                currentIndex = 0
            }
            isPlaying = false
            progress = 0
            // Parked at the start of the next track: show its length, as a
            // paused speaker would, rather than no scrubber at all.
            duration = catalogDuration(at: currentIndex)
            return
        }
        if repeatMode == .one {
            Task { try? await arm(at: end) }
            return
        }
        guard end + 1 < queue.count else {
            if repeatMode == .all, !queue.isEmpty {
                Task { try? await arm(at: 0) }
            } else {
                stop()
            }
            return
        }
        Task { try? await arm(at: end + 1) }
    }

    private func restartCurrent() {
        switch backend {
        case .appleMusic:
            musicPlayer.restartCurrentEntry()
        case .stream:
            streamPlayer?.seek(to: .zero)
        case .appleStation:
            break
        case nil:
            // From the top, not from where a restored track was.
            resumePosition = nil
            Task { try? await arm(at: currentIndex) }
        }
    }

    /// Silences whichever player is armed. Sets `backend` to nil first so the
    /// poll can't misread the teardown as a run ending.
    private func teardownRun() {
        let previous = backend
        backend = nil
        runEnd = -1
        appleRun = []
        appleWasPlaying = false
        audioQualityTask?.cancel()
        audioQualityTask = nil
        audioQualityItem = nil
        audioVariantEntryID = nil
        if audioQuality != nil {
            audioQuality = nil
        }
        stationMetadataTask?.cancel()
        stationMetadataTask = nil
        streamMetadataListener = nil
        liveMetadata = nil

        if previous == .appleMusic || previous == .appleStation {
            musicPlayer.stop()
        }
        if streamPlayer != nil {
            streamPlayer?.pause()
            streamPlayer?.removeAllItems()
            streamPlayer = nil
            streamRun = [:]
            nowPlayingCard.end()
            isPlayingLocalStream = false
            // Hand the audio session back to whatever held it behind us (see
            // `AudioSessionArbiter`), otherwise release it entirely.
            if !AudioSessionArbiter.shared.handBack() {
                try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            }
        }
    }

    /// Drops everything after the current track from the armed player, so the
    /// run ends there and queue order changes take effect (see `playNext`).
    private func truncateArmedRunAfterCurrent() {
        switch backend {
        case .appleStation:
            break
        case .appleMusic:
            var entries = musicPlayer.queue.entries
            if let current = musicPlayer.queue.currentEntry,
               let index = entries.firstIndex(where: { $0.id == current.id }) {
                let after = entries.index(after: index)
                if after < entries.endIndex {
                    entries.removeSubrange(after...)
                    musicPlayer.queue.entries = entries
                }
            }
        case .stream:
            if let streamPlayer {
                for item in streamPlayer.items().dropFirst() {
                    streamPlayer.remove(item)
                }
            }
        case nil:
            break
        }
        runEnd = currentIndex
    }

    // MARK: - Apple Music backend

    private func armApple(index: Int, end: Int, token: Int, resume: TimeInterval? = nil) async throws {
        isLoading = true
        defer { if playToken == token { isLoading = false } }

        // Resolve the whole run in one catalog request (cache-first), keeping
        // track of which queue rows made it — a failed row is skipped, not
        // fatal to the run.
        var resolved: [(queueIndex: Int, song: Song)] = []
        var missing: [(queueIndex: Int, catalogID: String)] = []
        var cacheChanged = false
        for queueIndex in index...end {
            let item = queue[queueIndex]
            // Library tracks resolve from the library itself. Going through the
            // catalog first was why playing one sometimes did nothing: a
            // library-only track — a matched upload, or a purchase Apple Music
            // doesn't carry — has no catalog equivalent, so `catalogID` came
            // back nil and the row was silently dropped from the run.
            if item.content.type == .libraryTrack {
                let key = Self.libraryCacheKey(for: item.content.id)
                if let cached = songCache[key] {
                    resolved.append((queueIndex, cached))
                    continue
                }
                if let song = await librarySong(id: item.content.id) {
                    songCache[key] = song
                    cacheChanged = true
                    resolved.append((queueIndex, song))
                    continue
                }
                // Not in the library any more — fall through and try the
                // catalog mapping rather than dropping the row outright.
            }
            guard let catalogID = await catalogID(for: item) else { continue }
            if let cached = songCache[catalogID] {
                resolved.append((queueIndex, cached))
            } else {
                missing.append((queueIndex, catalogID))
            }
        }
        if !missing.isEmpty {
            let fetched = try await MusicSearchService.shared.appleSongs(ids: missing.map(\.catalogID))
            let byID = Dictionary(fetched.map { ($0.id.rawValue, $0) }, uniquingKeysWith: { first, _ in first })
            for (queueIndex, catalogID) in missing {
                guard let song = byID[catalogID] else { continue }
                songCache[catalogID] = song
                cacheChanged = true
                resolved.append((queueIndex, song))
            }
        }
        if cacheChanged {
            SongDiskCache.save(songCache)
        }
        resolved.sort { $0.queueIndex < $1.queueIndex }

        // The user skipped elsewhere while we were resolving — that call owns
        // playback now.
        guard playToken == token else { return }
        guard let first = resolved.first else {
            // Nothing in this run resolved (e.g. region-unavailable tracks) —
            // a lone track is an error worth surfacing, otherwise skip on.
            if end + 1 < queue.count {
                advancePastRun(endingAt: end)
                return
            }
            throw LocalPlaybackError.songNotFound
        }

        musicPlayer.queue = ApplicationMusicPlayer.Queue(for: resolved.map(\.song), startingAt: first.song)
        if let resume, resume > 0 {
            // Point the player partway in before it starts. A seek issued
            // after `play()` returns is dropped while the entry is still
            // preparing, which started a hand-off's track from the top.
            try await musicPlayer.prepareToPlay()
            guard playToken == token else { return }
            musicPlayer.playbackTime = resume
        }
        try await musicPlayer.play()
        guard playToken == token else { return }

        appleRun = resolved
        backend = .appleMusic
        runEnd = end
        currentIndex = first.queueIndex
        duration = first.song.duration ?? catalogDuration(at: first.queueIndex)
    }

    /// Hands an Apple Music station to the Apple player. Stations are
    /// `PlayableMusicItem`s in their own right, so no song resolution — the
    /// player runs the station's stream of tracks itself.
    private func armAppleStation(index: Int, token: Int) async throws {
        isLoading = true
        defer { if playToken == token { isLoading = false } }

        let item = queue[index]
        let request = MusicCatalogResourceRequest<Station>(matching: \.id, equalTo: MusicItemID(item.content.id))
        guard let station = try? await request.response().items.first else {
            if index + 1 < queue.count {
                advancePastRun(endingAt: index)
                return
            }
            throw LocalPlaybackError.stationNotFound
        }
        guard playToken == token else { return }

        musicPlayer.queue = ApplicationMusicPlayer.Queue(for: [station])
        try await musicPlayer.play()
        guard playToken == token else { return }

        appleRun = []
        backend = .appleStation
        runEnd = index
        currentIndex = index
        duration = 0
    }

    /// Cache key for a library `Song`. Namespaced so a library id can't collide
    /// with the catalog ids the rest of the cache holds.
    private static func libraryCacheKey(for id: String) -> String { "library:\(id)" }

    /// The library `Song` for a library-track row, queued directly rather than
    /// via its catalog twin — `ApplicationMusicPlayer` plays library items, and
    /// this is the only path that works for a track the catalog doesn't have.
    private func librarySong(id: String) async -> Song? {
        var request = MusicLibraryRequest<Song>()
        request.filter(matching: \.id, equalTo: MusicItemID(id))
        return try? await request.response().items.first
    }

    /// The Apple Music catalog id for `item`. Library tracks carry a library id
    /// (`i.…`) the catalog can't fetch, so those are mapped to their catalog
    /// song first — the same way radio seeding does.
    private func catalogID(for item: PlayableContent) async -> String? {
        guard item.content.type == .libraryTrack else { return item.content.id }
        guard let lookup = await MusicSearchService.shared.appleLibraryLookup(id: item.content.id) else { return nil }
        return lookup.data.first?.id
    }

    // MARK: - Playback cache

    private func cacheNeedsRefresh() {
        cacheRefreshTask?.cancel()
        cacheRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            PlaybackCache.shared.queueDidChange(self.queue, currentIndex: self.currentIndex)
        }
    }

    /// The cache finished a song that may be sitting in the armed run
    /// already, as a stream. Swapping its player item for the local file
    /// means the run plays it from disk when it gets there — the difference
    /// between a tunnel passing unnoticed and a stall.
    func cachedCopyLanded(for item: PlayableContent, at url: URL) {
        guard backend == .stream, let streamPlayer else { return }
        for playerItem in streamPlayer.items() {
            guard let queueIndex = streamRun[ObjectIdentifier(playerItem)],
                  queueIndex > currentIndex,
                  queue[safe: queueIndex]?.content.id == item.content.id else { continue }
            let replacement = AVPlayerItem(url: url)
            guard streamPlayer.canInsert(replacement, after: playerItem) else { return }
            streamPlayer.insert(replacement, after: playerItem)
            streamPlayer.remove(playerItem)
            streamRun[ObjectIdentifier(playerItem)] = nil
            streamRun[ObjectIdentifier(replacement)] = queueIndex
            return
        }
    }

    // MARK: - Stream (Plex, Subsonic, TuneIn) backend

    /// What the stream player opens for `item`. A local copy beats the
    /// server URL — a download, or the cache's copy — since it plays with no
    /// network, including away from the server entirely. A TuneIn station
    /// has no URL of its own until its id is resolved.
    private func streamURL(for item: PlayableContent) async -> URL? {
        if item.content.service == .tuneIn, item.content.type == .radio {
            return await MusicSearchService.shared.tuneInStreamURL(id: item.content.id)
        }
        // A local copy beats the server URL. The server URL is built now,
        // not read off the item, so the Streaming Quality setting in force
        // is the one used.
        return DownloadManager.shared.localURL(for: item)
            ?? PlaybackCache.shared.localURL(for: item)
            ?? item.playbackStreamURL
    }

    private func armStream(index: Int, end: Int, token: Int, resume: TimeInterval? = nil) async throws {
        // A Files song still in iCloud can't be handed to the player: there
        // is no streaming from iCloud Drive, and a read of the placeholder
        // blocks until the whole file is down. Fetch it first, showing the
        // wait as loading, and stop the run at the next one still up there
        // — the cache asks for those ahead, so by the time the run ends it
        // is usually already here.
        if let pending = cloudPendingURL(for: queue[index]) {
            isLoading = true
            defer { if playToken == token { isLoading = false } }
            FilesLibraryService.shared.downloadFromCloud(trackIDs: [queue[index].content.id], keep: !PlaybackCache.shared.streamsFromCloud)
            let landed = await Self.waitForCloudFile(at: pending)
            guard playToken == token else { return }
            guard landed else {
                AlertService.shared.showAlert(with: "Couldn't get “\(queue[index].title)” from iCloud", imageName: "icloud.slash")
                advancePastRun(endingAt: index)
                return
            }
        }

        // Only a station has to go to the network for its URL; tracks
        // answer at once, so the flag is only up when it means something.
        let needsResolving = isStation(queue[index])
        if needsResolving { isLoading = true }
        defer { if needsResolving, playToken == token { isLoading = false } }

        var rows: [(queueIndex: Int, item: AVPlayerItem)] = []
        var lastArmed = index
        for queueIndex in index...end {
            let item = queue[queueIndex]
            // A later song still in iCloud ends the run here; the next arm
            // fetches it.
            if queueIndex > index, cloudPendingURL(for: item) != nil { break }
            guard let url = await streamURL(for: item) else { continue }
            let playerItem = AVPlayerItem(url: url)
            if isStation(item) {
                listenForStreamTitles(on: playerItem, token: token)
                applyStationAudioTap(to: playerItem)
            }
            rows.append((queueIndex, playerItem))
            lastArmed = queueIndex
        }
        // The user skipped elsewhere while a station resolved — that call
        // owns playback now.
        guard playToken == token else { return }
        guard !rows.isEmpty else {
            advancePastRun(endingAt: lastArmed)
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print(error)
        }

        streamRun = Dictionary(uniqueKeysWithValues: rows.map { (ObjectIdentifier($0.item), $0.queueIndex) })
        let player = AVQueuePlayer(items: rows.map(\.item))
        streamPlayer = player
        applyStreamVolume()
        if let resume, resume > 0 {
            // Partway in before the first note, so nothing from the top of
            // the track is heard first. Pending until the item is ready, so
            // not awaited — it lands before playback does.
            player.seek(to: CMTime(seconds: resume, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
        }
        player.play()

        backend = .stream
        runEnd = lastArmed
        currentIndex = rows[0].queueIndex
        if let station = queue[safe: currentIndex], isStation(station) {
            pollStationMetadata(for: station, token: token)
        }
        isPlayingLocalStream = true
        nowPlayingCard.begin()
        nowPlayingCard.update(
            item: nowPlayingDisplay,
            isPlaying: true,
            duration: 0,
            elapsed: resume ?? 0,
            canSkip: currentIndex + 1 < queue.count
        )
    }

    /// The file URL of a Files song that is still only in iCloud, or nil
    /// when it is here (or not an iCloud file at all).
    private func cloudPendingURL(for item: PlayableContent) -> URL? {
        guard item.content.service == .files, let url = item.previewURL else { return nil }
        switch FilesLibraryService.shared.cloudStatus(trackID: item.content.id) {
        case .local, .notCloud:
            return nil
        case .downloading, .notDownloaded:
            return url
        }
    }

    /// Waits for iCloud to bring the file down. False on giving up: a long
    /// enough wait for a large file on a slow link, not for ever.
    private static func waitForCloudFile(at url: URL) async -> Bool {
        let deadline = Date.now.addingTimeInterval(5 * 60)
        while Date.now < deadline, !Task.isCancelled {
            let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            switch values?.ubiquitousItemDownloadingStatus {
            case .current?, .downloaded?:
                return true
            case nil where FileManager.default.fileExists(atPath: url.path):
                // Not an iCloud placeholder after all — nothing to wait for.
                return true
            default:
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        return false
    }

    // MARK: - Station metadata

    /// TuneIn's station lookup says what's on air — the same call the Sonos
    /// player makes for a TuneIn stream. Polled, since nothing pushes it;
    /// the ICY listener below fills the gap between polls.
    private func pollStationMetadata(for station: PlayableContent, token: Int) {
        stationMetadataTask?.cancel()
        stationMetadataTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.playToken == token else { return }
                if let info = await MusicSearchService.shared.lookupTuneInStation(id: station.content.id)?.stationInfo {
                    await self.noteOnAir(song: info.song, artist: info.artist, token: token)
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// ICY metadata rides inside most MP3 and AAC streams as a title line the
    /// moment a song changes, well ahead of TuneIn's next poll.
    private func listenForStreamTitles(on playerItem: AVPlayerItem, token: Int) {
        let listener = StreamMetadataListener { [weak self] title in
            guard let self, self.playToken == token else { return }
            // The convention is "Artist - Title"; a bare line is the song.
            let parts = title.components(separatedBy: " - ")
            if parts.count >= 2 {
                await self.noteOnAir(song: parts.dropFirst().joined(separator: " - "), artist: parts[0], token: token)
            } else {
                await self.noteOnAir(song: title, artist: nil, token: token)
            }
        }
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(listener, queue: .main)
        playerItem.add(output)
        streamMetadataListener = listener
    }

    /// Takes a new song on air and looks its artwork up the way the Sonos
    /// player does. A station that reports nothing keeps whatever the
    /// stream itself last said.
    private func noteOnAir(song: String?, artist: String?, token: Int) async {
        guard playToken == token else { return }
        let song = song?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = trimmedArtist.flatMap { $0.isEmpty ? nil : $0 }
        guard !song.isEmpty else { return }
        // TuneIn sometimes hands the station's own name back as the song.
        guard song != nowPlaying?.title else { return }
        guard liveMetadata?.song != song || liveMetadata?.artist != artist else { return }
        // The song Shazam already named, in the station's own words ("Just
        // Dance" for "Just Dance (feat. Colby O'Donis)") — keep the match
        // and its cover rather than blanking the art for a lookup.
        if let live = liveMetadata, live.artworkURL != nil, Self.isSameSong(live.song, song) { return }

        let live = LiveStationMetadata(song: song, artist: artist, artworkURL: nil)
        liveMetadata = live
        await lookUpArtwork(for: live, token: token)
    }

    /// Finds a cover for what's on air the way the Sonos player does, and
    /// puts it up if nothing else has come on air meanwhile.
    private func lookUpArtwork(for live: LiveStationMetadata, token: Int) async {
        let results = await MusicSearchService.shared.search(song: live.song, artist: live.artist ?? "", album: "")
        guard playToken == token, liveMetadata == live, let result = results.first else { return }
        let match = PlayableContent(
            title: result.trackName,
            subtitle: result.artistName,
            thumbnail: URL(string: result.artworkURL(with: "100")),
            artwork: URL(string: result.artworkURL(with: "600")),
            content: MediaContent(service: .apple, id: result.trackID.description, type: .track, location: URL(string: result.trackViewURL)),
            metadata: PlayableContentMetadata(
                artist: result.artistName,
                artistID: result.artistID.description,
                album: result.album,
                albumID: result.collectionID?.description
            )
        )
        if liveMetadata?.artworkURL == nil {
            liveMetadata?.artworkURL = match.artwork
        }
        if liveMetadata?.match == nil {
            liveMetadata?.match = match
        }
    }

    /// The Apple Music song on air, while a station plays and one was found.
    var onAirMatch: PlayableContent? {
        guard let item = nowPlaying, isStation(item) else { return nil }
        return liveMetadata?.match
    }

    /// Whether two titles name the same song, ignoring case and anything in
    /// brackets (features, remix and edit tags).
    private static func isSameSong(_ lhs: String, _ rhs: String) -> Bool {
        func core(_ title: String) -> String {
            title.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }
        let (a, b) = (core(lhs), core(rhs))
        return !a.isEmpty && a == b
    }

    // MARK: - Song recognition

    /// A TuneIn station: the one kind that plays as a stream here (see
    /// `backendKind(for:)`). An Apple Music station already names every
    /// song it plays. Read off the queue row rather than `backend` so a
    /// view showing the button follows it.
    var canRecognizeSong: Bool {
        guard let item = nowPlaying else { return false }
        return item.content.service == .tuneIn && item.content.type == .radio
    }

    /// The stream of the station playing here, for `SongRecognizer` to
    /// listen to.
    func currentStationStreamURL() async -> URL? {
        guard canRecognizeSong, let station = nowPlaying else { return nil }
        return await streamURL(for: station)
    }

    /// Hands the station playing here to `onAudio` as it plays — its own
    /// audio, straight off the player, with where each chunk sits on the
    /// player's timeline (`stationPlayhead`). Stays on through re-arms of
    /// the station until `untapStationAudio()`.
    @available(iOS 27.0, visionOS 27.0, *)
    func tapStationAudio(_ onAudio: @escaping @Sendable (AVAudioPCMBuffer, CMTime) -> Void) {
        stationAudioTap = onAudio
        if let item = streamPlayer?.currentItem, isPlayingStation {
            applyStationAudioTap(to: item)
        }
    }

    func untapStationAudio() {
        guard stationAudioTap != nil else { return }
        stationAudioTap = nil
        if let item = streamPlayer?.currentItem, isPlayingStation {
            applyStationAudioTap(to: item)
        }
    }

    /// Where the station is on its own timeline — what's being heard, on
    /// whichever output — in the terms `tapStationAudio(_:)` stamps its
    /// audio with. Nil when no station is playing here.
    var stationPlayhead: TimeInterval? {
        guard isPlayingStation, let player = streamPlayer else { return nil }
        let time = player.currentTime()
        return time.isNumeric ? time.seconds : nil
    }

    private func applyStationAudioTap(to item: AVPlayerItem) {
        guard #available(iOS 27.0, visionOS 27.0, *) else { return }
        let gain = stationTapGain
        item.audioMix = stationAudioTap.flatMap { PlayerAudioTap.audioMix(gain: gain, onAudio: $0) }
        if item.audioMix != nil {
            tappedItem = item
        } else if tappedItem === item {
            tappedItem = nil
        }
        applyStreamVolume()
    }

    /// Sets the stream's level: on the player, or — for the tapped station —
    /// in the tap, with the player held at full level for it to hear.
    private func applyStreamVolume() {
        stationTapGain.value = streamVolume
        guard let player = streamPlayer else { return }
        let isTapped = tappedItem != nil && player.currentItem === tappedItem
        player.volume = isTapped ? 1 : streamVolume
    }

    /// Shows a song Shazam named as what's on air, as if the station had
    /// said so itself. Ignored when `stationID` is no longer the station
    /// playing.
    func noteRecognized(_ song: RecognizedSong, stationID: String?) {
        guard canRecognizeSong, nowPlaying?.content.id == stationID else { return }
        // Shazam's cover first, then the Apple Music song's; failing either
        // the cover or the song, the same lookup a station's own title gets.
        let live = LiveStationMetadata(
            song: song.title,
            artist: song.artist,
            artworkURL: song.artworkURL ?? song.playable?.artwork ?? song.playable?.thumbnail,
            match: song.playable
        )
        liveMetadata = live
        if live.artworkURL == nil || live.match == nil {
            let token = playToken
            Task { await lookUpArtwork(for: live, token: token) }
        }
    }

    // MARK: - State polling

    /// One slow poll drives all the observable state for both backends —
    /// MusicKit exposes `playbackTime` without observation, and it keeps the
    /// stream path symmetric instead of juggling KVO + time observers. It also
    /// tracks which queue row the armed player has advanced to, and notices a
    /// run ending so the next one gets armed.
    private func startPolling() {
        guard poller == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshState() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poller = timer
    }

    private func refreshState() {
        switch backend {
        case .appleMusic, .appleStation:
            let status = musicPlayer.state.playbackStatus
            // Every property here is observed by the player screen, and
            // `@Observable` notifies on every write, equal or not — so only
            // `progress` is written each tick. Writing the rest unchanged
            // re-rendered the whole screen twice a second, artwork and
            // blurred backdrop included, which is what made the scrubber's
            // fill stutter between polls.
            let playing = status == .playing
            let paused = isPlaying && !playing
            if isPlaying != playing { isPlaying = playing }
            progress = Self.finite(musicPlayer.playbackTime, else: progress)
            if playing { appleWasPlaying = true }
            savePositionIfDue(paused: paused)

            // A station's entries are the songs it streams; the current one
            // is what's on air.
            if backend == .appleStation, let entry = musicPlayer.queue.currentEntry {
                let live = LiveStationMetadata(
                    song: entry.title,
                    artist: entry.subtitle,
                    artworkURL: entry.artwork?.url(width: 600, height: 600)
                )
                if live != liveMetadata { liveMetadata = live }
            }

            // Follow the player's own advance through the run.
            let entries = musicPlayer.queue.entries
            if let current = musicPlayer.queue.currentEntry,
               let entryIndex = entries.firstIndex(where: { $0.id == current.id }) {
                let offset = entries.distance(from: entries.startIndex, to: entryIndex)
                if let row = appleRun[safe: offset] {
                    if currentIndex != row.queueIndex { currentIndex = row.queueIndex }
                    let songDuration = row.song.duration ?? catalogDuration(at: row.queueIndex)
                    if duration != songDuration { duration = songDuration }
                }
                // What the player is actually decoding, not what the catalog
                // offers — the person's Music settings decide between them.
                // Read once the entry is playing, and again over its first
                // seconds while the answer is still empty: the variant lands
                // a moment after playback starts.
                if playing, audioVariantEntryID != current.id || (audioQuality == nil && progress < 5) {
                    audioVariantEntryID = current.id
                    let quality = Self.quality(for: musicPlayer.state.audioVariant)
                    if quality != audioQuality {
                        audioQuality = quality
                    }
                }
            }

            // Run ended: the player ran off the end of its queue. `.stopped`
            // is the clean signal; the paused-at-the-end read covers OS
            // versions that park at `.paused` on the last entry instead.
            let onLastEntry = currentIndex >= (appleRun.last?.queueIndex ?? currentIndex)
            let ended = status == .stopped
                || (status == .paused && onLastEntry && duration > 0 && progress >= duration - 0.75)
            if appleWasPlaying, ended {
                appleWasPlaying = false
                let end = runEnd
                teardownRun()
                advancePastRun(endingAt: end)
            }
        case .stream:
            guard let streamPlayer else { return }
            guard let current = streamPlayer.currentItem else {
                // Ran off the end of the queue.
                let end = runEnd
                teardownRun()
                advancePastRun(endingAt: end)
                return
            }
            // An item that couldn't load parks the queue player on it:
            // paused, no length, and Play does nothing. Say so and move on
            // to the next item — with nothing after it, `currentItem` goes
            // nil and the next poll ends the run.
            if current.status == .failed {
                if let queueIndex = streamRun[ObjectIdentifier(current)],
                   let item = queue[safe: queueIndex] {
                    AlertService.shared.showAlert(with: "Couldn't play “\(item.title)”", imageName: "exclamationmark.triangle")
                }
                streamPlayer.advanceToNextItem()
                return
            }
            // Only what changed, as above.
            let playing = streamPlayer.timeControlStatus != .paused
            let paused = isPlaying && !playing
            if isPlaying != playing { isPlaying = playing }
            progress = Self.finite(current.currentTime().seconds, else: progress)
            savePositionIfDue(paused: paused)
            if let queueIndex = streamRun[ObjectIdentifier(current)], currentIndex != queueIndex {
                currentIndex = queueIndex
            }
            // `AVPlayerItem.duration` is indefinite until the item is ready
            // to play — and for good if it never gets there. The catalog's
            // length stands in until then so the scrubber doesn't vanish.
            let total = current.duration.seconds
            let itemDuration = total.isFinite && total > 0 ? total : catalogDuration(at: currentIndex)
            if duration != itemDuration { duration = itemDuration }
            if audioQualityItem != ObjectIdentifier(current) {
                audioQualityItem = ObjectIdentifier(current)
                readAudioQuality(of: current)
            }
            nowPlayingCard.update(
                item: nowPlayingDisplay,
                isPlaying: isPlaying,
                duration: duration,
                elapsed: progress,
                canSkip: currentIndex + 1 < queue.count
            )
        case nil:
            if isPlaying { isPlaying = false }
        }
    }

    // MARK: - Surviving a relaunch

    /// Loads the queue the last run of the app left, paused on the track it
    /// was playing with the scrubber where it was. Whatever the route: on a
    /// speaker route this is the queue `park()` left behind when the speaker
    /// took over, and it waits for the route to come back the same way.
    /// `PlaybackRoute` only carries it onto a speaker when the device is the
    /// source, so it can't be dragged onto the next speaker chosen.
    private func restoreSavedQueue() {
        guard let saved = LocalQueueStore.load(), !saved.queue.isEmpty else { return }
        // Only what the queue would take today: a row an earlier build let
        // in — a station, say — would otherwise sit at the front of the
        // player for good, and be carried onto every speaker chosen.
        let kept = saved.queue.filter { canPlayLocally($0) }
        guard !kept.isEmpty else {
            LocalQueueStore.clear()
            return
        }
        isRestoring = true
        defer { isRestoring = false }
        source = saved.source
        let current = saved.queue[safe: saved.position.index]
        let currentKept = current.flatMap { kept.firstIndex(of: $0) }
        queue = kept
        currentIndex = currentKept ?? 0
        repeatMode = saved.position.repeatMode
        // The position belongs to the track that was current; with that
        // one dropped, the queue starts from the top of what's left.
        duration = currentKept == nil ? 0 : Self.finite(saved.position.duration, else: 0)
        // Under a couple of seconds is the start of the track as far as
        // anyone can tell, the same cutoff a route switch uses.
        if currentKept != nil, saved.position.progress.isFinite, saved.position.progress > 2 {
            progress = saved.position.progress
            resumePosition = saved.position.progress
        }
        savedProgress = progress
        // The observer may or may not run for an assignment in `init`; the
        // cache wants to know either way, and the call is debounced.
        cacheNeedsRefresh()
    }

    private func queueNeedsSave() {
        guard !isRestoring else { return }
        queueNeedsWrite = true
        queueSaveTask?.cancel()
        queueSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.writeQueue()
        }
    }

    /// Hands the queue to the store, which encodes and writes it off the
    /// main thread — a queue can run to thousands of rows.
    private func writeQueue() {
        queueNeedsWrite = false
        LocalQueueStore.save(queue: queue)
    }

    /// Writes where the queue is — index, progress, duration, repeat mode.
    /// A handful of scalars in the defaults, cheap enough to write on every
    /// index change.
    private func savePosition() {
        guard !isRestoring, !queue.isEmpty else { return }
        savedProgress = progress
        LocalQueueStore.save(position: .init(index: currentIndex, progress: progress, duration: duration, repeatMode: repeatMode))
    }

    /// Writes what the queue was played from, so the player still names the
    /// origin after a relaunch. Written only when it changes, which is once
    /// per Play.
    private func saveSource() {
        guard !isRestoring else { return }
        LocalQueueStore.save(source: source)
    }

    /// The poll's version: every few seconds of progress, and at the moment
    /// playback pauses so the saved spot is the one the scrubber shows.
    private func savePositionIfDue(paused: Bool) {
        if paused || abs(progress - savedProgress) >= 5 {
            savePosition()
        }
    }

    /// Everything, now — for the moments the app may not get another chance.
    private func flushSavedState() {
        guard !isRestoring else { return }
        if queueNeedsWrite {
            queueSaveTask?.cancel()
            queueSaveTask = nil
            queueNeedsWrite = false
            // Waited for: the app may be about to suspend, and a write still
            // pending on the store's queue would be left half done.
            LocalQueueStore.save(queue: queue, waitUntilDone: true)
        }
        savePosition()
    }

    /// A player's clock as a number the rest of the app can use.
    ///
    /// `ApplicationMusicPlayer.playbackTime` is NaN while its entry is still
    /// loading — a station's first track, say — and `CMTime.seconds` is NaN
    /// for an invalid time. Published as `progress`, that reached the player
    /// screen as `Duration.seconds(progress)`, which traps on a non-finite
    /// value ("Double value cannot be converted to _Int128"). So the clock is
    /// read through here: a finite time is clamped at zero, anything else
    /// leaves `fallback` — usually the last good reading — in place.
    private static func finite(_ time: TimeInterval, else fallback: TimeInterval) -> TimeInterval {
        time.isFinite ? max(0, time) : fallback
    }

    // MARK: - Audio quality

    /// The Sonos-shaped quality for what Apple's player says it is playing.
    /// Nothing for plain lossy stereo — there is nothing to badge.
    private static func quality(for variant: AudioVariant?) -> SonosTrackQuality? {
        guard let variant else { return nil }
        switch variant {
        case .dolbyAtmos, .dolbyAudio, .spatialAudio:
            return SonosTrackQuality(lossless: false, immersive: true)
        case .highResolutionLossless:
            return SonosTrackQuality(bitDepth: 24, lossless: true, immersive: false)
        case .lossless:
            return SonosTrackQuality(lossless: true, immersive: false)
        default:
            return nil
        }
    }

    /// Reads the format of a stream item off its asset: the codec decides
    /// lossless, the stream description carries the sample rate, and for
    /// FLAC and ALAC the format flags say what bit depth the source was.
    private func readAudioQuality(of item: AVPlayerItem) {
        audioQualityTask?.cancel()
        if audioQuality != nil {
            audioQuality = nil
        }
        let asset = item.asset
        audioQualityTask = Task { [weak self] in
            let quality = await Self.quality(for: asset)
            guard !Task.isCancelled, let self, self.audioQualityItem == ObjectIdentifier(item) else { return }
            if quality != self.audioQuality {
                self.audioQuality = quality
            }
        }
    }

    private static func quality(for asset: AVAsset) async -> SonosTrackQuality? {
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let descriptions = try? await track.load(.formatDescriptions),
              let description = descriptions.first,
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
            return nil
        }

        let lossless = [kAudioFormatFLAC, kAudioFormatAppleLossless, kAudioFormatLinearPCM].contains(stream.mFormatID)
        let sampleRate = stream.mSampleRate > 0 ? Int(stream.mSampleRate) : nil

        var bitDepth: Int?
        if stream.mBitsPerChannel > 0 {
            bitDepth = Int(stream.mBitsPerChannel)
        } else if lossless {
            // Compressed lossless leaves `mBitsPerChannel` at zero; the source
            // depth rides in the flags instead, the same set for both codecs.
            switch stream.mFormatFlags {
            case kAppleLosslessFormatFlag_16BitSourceData: bitDepth = 16
            case kAppleLosslessFormatFlag_20BitSourceData: bitDepth = 20
            case kAppleLosslessFormatFlag_24BitSourceData: bitDepth = 24
            case kAppleLosslessFormatFlag_32BitSourceData: bitDepth = 32
            default: break
            }
        }

        guard lossless || sampleRate != nil else { return nil }
        return SonosTrackQuality(bitDepth: bitDepth, lossless: lossless, immersive: false, sampleRate: sampleRate)
    }
}

/// What a station is playing right now.
struct LiveStationMetadata: Equatable {
    var song: String
    var artist: String?
    var artworkURL: URL?
    /// The song in Apple Music's catalog, once found — what the player's
    /// title, artist, like button and menu act on while a station plays.
    var match: PlayableContent?
}

/// Hands ICY stream titles (`StreamTitle`) to a closure as they arrive.
private final class StreamMetadataListener: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    private let onTitle: @MainActor (String) async -> Void

    init(onTitle: @escaping @MainActor (String) async -> Void) {
        self.onTitle = onTitle
    }

    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        for group in groups {
            for item in group.items where item.identifier == .icyMetadataStreamTitle {
                Task {
                    guard let title = try? await item.load(.stringValue), !title.isEmpty else { return }
                    await onTitle(title)
                }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// On-disk copy of resolved `Song`s (they're Codable), so tracks Cue has seen
/// before re-arm with no catalog request — the piece that makes airplane-mode
/// playback of Music-app-downloaded songs possible.
private enum SongDiskCache {
    private static var url: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("AppleSongCache.json")
    }

    static func load() -> [String: Song] {
        guard let url, let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Song].self, from: data)) ?? [:]
    }

    static func save(_ cache: [String: Song]) {
        guard let url, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// The device queue and its position, kept across launches. The queue goes
/// in a file in Application Support beside the song cache — it can run to
/// thousands of rows — and the position, which changes far more often, in
/// the defaults as a few scalars. An empty queue clears both.
///
/// Queue writes go through one serial queue, in order, so a slow write of
/// an older copy can't land on top of a newer one.
private enum LocalQueueStore {
    private static let io = DispatchQueue(label: "dance.cue.localQueue", qos: .utility)

    struct Position: Codable {
        var index: Int
        var progress: TimeInterval
        var duration: TimeInterval
        var repeatMode: LocalPlaybackService.RepeatMode
    }

    struct Saved {
        var queue: [PlayableContent]
        var position: Position
        /// What the queue was played from, when it was played from anything.
        var source: PlayableContent?
    }

    private static var queueURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("LocalQueue.json")
    }

    private static var positionKey: String { AppStorageKeys.localQueuePosition }
    /// One row, so it sits in the defaults beside the position rather than
    /// in the queue file — which stays a bare `[PlayableContent]`, readable
    /// by builds that predate the origin.
    private static var sourceKey: String { AppStorageKeys.localQueueSource }

    static func load() -> Saved? {
        guard let queueURL, let data = try? Data(contentsOf: queueURL),
              let queue = try? JSONDecoder().decode([PlayableContent].self, from: data) else { return nil }
        let position = UserDefaults.standard.data(forKey: positionKey)
            .flatMap { try? JSONDecoder().decode(Position.self, from: $0) }
            ?? Position(index: 0, progress: 0, duration: 0, repeatMode: .off)
        let source = UserDefaults.standard.data(forKey: sourceKey)
            .flatMap { try? JSONDecoder().decode(PlayableContent.self, from: $0) }
        return Saved(queue: queue, position: position, source: source)
    }

    static func save(queue: [PlayableContent], waitUntilDone: Bool = false) {
        let work: @Sendable () -> Void = {
            guard !queue.isEmpty else { return Self.clear() }
            guard let url = Self.queueURL, let data = try? JSONEncoder().encode(queue) else { return }
            try? data.write(to: url, options: .atomic)
        }
        if waitUntilDone {
            io.sync(execute: work)
        } else {
            io.async(execute: work)
        }
    }

    static func save(position: Position) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        UserDefaults.standard.set(data, forKey: positionKey)
    }

    static func save(source: PlayableContent?) {
        guard let source, let data = try? JSONEncoder().encode(source) else {
            return UserDefaults.standard.removeObject(forKey: sourceKey)
        }
        UserDefaults.standard.set(data, forKey: sourceKey)
    }

    static func clear() {
        if let queueURL {
            try? FileManager.default.removeItem(at: queueURL)
        }
        UserDefaults.standard.removeObject(forKey: positionKey)
        UserDefaults.standard.removeObject(forKey: sourceKey)
    }
}
