import AVFoundation
import Defaults
import Foundation
import MusicKit
import Observation
import OSLog
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
///   A station isn't queued: it plays in front of the queue (`station`),
///   which waits behind it as it was, the way a speaker's queue waits
///   while it plays radio.
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
        // Ready before the first Apple song is asked for: an older build's
        // song file gets split up here, off the main thread.
        Task.detached(priority: .utility) {
            await AppleSongStore.shared.prepare()
        }
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
        // A stream run's last song ending is the cue to arm what follows,
        // straight away rather than on the next poll — up to half a second
        // of silence at every hand-off otherwise.
        observers.append(Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: AVPlayerItem.didPlayToEndTimeNotification) {
                guard let item = note.object as? AVPlayerItem else { continue }
                self?.streamItemDidFinish(ObjectIdentifier(item))
            }
        })
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

    /// One entry in the Apple player's queue: the queue row it plays and the
    /// song's length. Not the `Song` itself, which holds about 25 KB.
    private struct AppleRunEntry {
        let queueIndex: Int
        let duration: TimeInterval?

        init(_ resolved: (queueIndex: Int, song: Song)) {
            queueIndex = resolved.queueIndex
            duration = resolved.song.duration
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
    private(set) var isPlaying = false {
        didSet {
            guard isPlaying != oldValue else { return }
            // Stopping keeps the time that ran since the last reading, so a
            // bar stays where it was showing; starting only restarts the
            // clock, so time spent paused doesn't count.
            if oldValue { progressAnchor = runningProgress(at: .now) }
            progressAnchoredAt = .now
            if isPlaying { PlaybackRoute.shared.deviceStartedPlaying() }
        }
    }
    private(set) var isLoading = false
    /// Where playback is now, in seconds: the player's clock as last read,
    /// run forward while playing (see `estimatedProgress(at:)`). Writing it —
    /// a seek, a new song, a restore — sets the clock there.
    ///
    /// Not stored, so the poll doesn't have to write it: every write of an
    /// `@Observable` property invalidates every view reading it, and a
    /// reading taken twice a second re-rendered each progress display, the
    /// mini player included, for a number the clock already had. Views draw
    /// it through `PlaybackTimeline`, which redraws only as often as a pixel
    /// of progress and only while it's on screen.
    private(set) var progress: TimeInterval {
        get { estimatedProgress() }
        set {
            if progressAnchor != newValue { progressAnchor = newValue }
            progressAnchoredAt = .now
        }
    }
    private(set) var duration: TimeInterval = 0
    /// The clock's last setting, in seconds — see `progress`.
    private var progressAnchor: TimeInterval = 0
    /// When `progressAnchor` was set, or playback last started or stopped.
    @ObservationIgnored private var progressAnchoredAt: Date = .distantPast

    /// The station playing in front of the queue, or nil while the queue
    /// plays. Playing a station leaves the queue as it was: its songs, its
    /// place and the spot in the current song (`resumePosition`) wait behind
    /// the station, not in use, the way a speaker's queue waits while it
    /// plays radio. Anything that plays from the queue again (a row tapped,
    /// a new Play) puts the station away. Saved on its own, so a relaunch
    /// comes back to it.
    private(set) var station: PlayableContent? {
        didSet {
            guard !isRestoring, station != oldValue else { return }
            LocalQueueStore.save(station: station)
        }
    }

    var nowPlaying: PlayableContent? { station ?? queue[safe: currentIndex] }

    /// Whether a station is what's playing: nothing to scrub, nothing before
    /// it, and the queue behind it not in use.
    var isPlayingStation: Bool { station != nil }

    /// Whether the station playing is one of Apple Music's that runs as a
    /// stream of songs, so Next skips to its next song. Not a live one
    /// (Apple Music 1 and the rest of the broadcasts), which has nothing to
    /// skip to, any more than a TuneIn stream does.
    var isPlayingAppleStation: Bool {
        guard let station, station.content.service == .apple else { return false }
        return station.content.type != .liveRadio
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
    /// Per run, not per queue: an album played next inside an artist's run
    /// names its album, not the artist, and the artist's tracks after it
    /// still name the artist. Nil for a track that came as a bare track — a
    /// search result, a speaker hand-off — which has no origin to name.
    /// Nil while a station plays in front of the queue.
    var source: PlayableContent? {
        guard station == nil else { return nil }
        return queue[safe: currentIndex].flatMap { origins[$0.id] }
    }

    /// Each queued track's origin, by track ID. A track queued twice from
    /// two places keeps the later one.
    private var origins: [String: PlayableContent] = [:] {
        didSet { saveSource() }
    }

    /// Names `origin` as where `items` came from; nil forgets it.
    private func setOrigin(_ origin: PlayableContent?, for items: [PlayableContent]) {
        guard !items.isEmpty else { return }
        var updated = origins
        for item in items {
            updated[item.id] = origin
        }
        origins = updated
    }

    var upNext: [PlayableContent] { Array(queue.dropFirst(currentIndex + 1)) }
    /// `upNext.count` without copying it: a button's enabled state read the
    /// copy of a 1,700-song queue on every update.
    var upNextCount: Int { max(0, queue.count - currentIndex - 1) }
    var isActive: Bool { !queue.isEmpty || station != nil }
    /// Whether a skip forward has somewhere to go: another track, or the top
    /// of the queue again when it repeats. On a station, only an Apple Music
    /// one that skips its own songs.
    var hasNext: Bool {
        guard station == nil else { return isPlayingAppleStation }
        return currentIndex + 1 < queue.count || (repeatMode == .all && !queue.isEmpty)
    }

    /// How the queue loops. Repeat One shortens the armed run to the current
    /// track, so the native player hands back at the end of each one instead
    /// of sailing on to the next.
    private(set) var repeatMode: RepeatMode = .off
    /// Whether what's after the current track is in shuffled order. A
    /// switch, like the system player's: on shuffles Up Next, off puts it
    /// back. It used to be a one-off shuffle, which left no way back to the
    /// album's order.
    private(set) var isShuffled = false {
        didSet { if oldValue != isShuffled { savePosition() } }
    }
    /// Up Next in its real order while shuffle is on — the order it had
    /// before, kept up to date with what's added and removed meanwhile — for
    /// putting it back. Nil while shuffle is off. Saved with the queue, so a
    /// relaunch still knows the album's order.
    @ObservationIgnored private var unshuffledUpNext: [PlayableContent]? {
        didSet {
            guard !isRestoring else { return }
            LocalQueueStore.save(unshuffled: unshuffledUpNext)
        }
    }
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
    /// start`) when nothing is armed. For a stream run it's a window of the
    /// run, topped up as it plays — see `streamWindow`.
    @ObservationIgnored private var runEnd = -1
    /// Where an arm in flight is taking playback, until it lands. A skip
    /// pressed meanwhile goes on from there, not from the song being left:
    /// five presses during a re-arm move five songs, where each used to
    /// re-arm the same one.
    @ObservationIgnored private var armingIndex: Int?

    /// How many songs a stream run hands its player at a time.
    ///
    /// `AVQueuePlayer` only buffers the song after the current one, but every
    /// `AVPlayerItem` costs about 60 KB of player machinery — dozens of
    /// notification listeners, dispatch queues and timebases — the moment it
    /// exists. Arming a 1,700-song Plex playlist whole made 1,700 of them:
    /// ~100 MB and four seconds of main-thread work before the first note,
    /// and again on every Previous or row tap. The rest of the run follows a
    /// few songs ahead of playback (`topUpStreamRun`).
    private static let streamWindow = 10
    /// The window is topped back up once fewer than this many armed songs
    /// are left after the current one.
    private static let streamTopUpThreshold = 4
    /// How many songs an Apple run starts with. The rest follow into the
    /// player's queue once it's playing (`fillAppleRun`).
    ///
    /// Every song has to be looked up before the Apple player will take it,
    /// and the player's own queue load grows with its length: a 600-song
    /// library list took 8.6 s to its first note when armed whole, 3.5 s
    /// with every song already looked up, and Previous re-armed all of it
    /// again (11 s for three presses).
    private static let appleWindow = 20
    /// How far ahead of the song playing the Apple player's queue is kept.
    /// Not the whole run, which costs memory for every song queued; but
    /// generous, because Cue is suspended in the background while Apple's
    /// player plays on by itself, and these are what play until Cue is next
    /// awake to add more — 200 songs is about twelve hours.
    private static let appleQueueAhead = 200
    /// The least time between two inserts into the Apple player's queue.
    /// Inserts made back to back — four within 150 ms — stop the player a
    /// second or so later, with no error; one insert, or inserts a second
    /// apart, don't.
    private static let appleInsertSpacing: TimeInterval = 2
    @ObservationIgnored private let musicPlayer = ApplicationMusicPlayer.shared
    /// The armed Apple run, one per player entry: its queue row and the
    /// song's length. Rows that failed to resolve have no entry, which is why
    /// this maps entry offsets to queue indices instead of assuming they line
    /// up.
    @ObservationIgnored private var appleRun: [AppleRunEntry] = []
    /// The rest of the Apple run being looked up and handed to the player,
    /// and the arm it belongs to (see `fillAppleRun`).
    @ObservationIgnored private var appleFill: (token: Int, task: Task<Void, Never>)?
    /// No fill before this: the last one failed (no network, say), and the
    /// poll would otherwise try again every half second.
    @ObservationIgnored private var appleFillRetryAfter: Date = .distantPast
    /// When songs were last inserted into the Apple player's queue (see
    /// `appleInsertSpacing`).
    @ObservationIgnored private var lastAppleInsert: Date = .distantPast
    /// The queue row the Apple player last stopped short on and was armed
    /// again at — once, so a song it keeps stopping on is gone past instead.
    @ObservationIgnored private var appleStallIndex: Int?
    /// Where an Apple skip took the queue, shown at once and held over the
    /// poll until the player gets there: MusicKit's current entry follows a
    /// skip a beat later, and the poll would put the old song back meanwhile.
    @ObservationIgnored private var appleSkipHold: (queueIndex: Int, until: Date)?
    /// Set once the Apple player has actually played, so a `.stopped` read
    /// means "run ended", not "still warming up".
    @ObservationIgnored private var appleWasPlaying = false
    /// When the run's last entry will finish, by the wall clock, as of the
    /// last poll that saw it playing. Nil until the last entry plays. The
    /// Apple player can finish its queue by pausing and rewinding to zero
    /// rather than reading `.stopped`, which looks just like a pause — this
    /// is what tells the two apart, including after the app slept through
    /// the end in the background and no poll saw the last seconds.
    @ObservationIgnored private var appleRunExpectedEnd: Date?
    @ObservationIgnored private var streamPlayer: AVQueuePlayer?
    /// Reads ICY stream titles off a station's player item.
    @ObservationIgnored private var streamMetadataListener: StreamMetadataListener?
    /// Polls TuneIn for what the current station is playing.
    @ObservationIgnored private var stationMetadataTask: Task<Void, Never>?
    /// The stream player's own output level, 0...1 — `DeviceVolume` drives
    /// it where the device volume can't be set. Carried onto each new run.
    @ObservationIgnored var streamVolume: Float = 1 {
        didSet { streamPlayer?.volume = streamVolume }
    }
    /// The armed stream run: player item → queue index.
    @ObservationIgnored private var streamRun: [ObjectIdentifier: Int] = [:]
    /// The player item of a TuneIn station playing in front of the queue
    /// (`station`), which has no queue index to go under in `streamRun`.
    @ObservationIgnored private var stationItem: ObjectIdentifier?
    /// Since when a TuneIn station's stream has stood paused, for
    /// `liveResumeLimit`. Nil while it plays.
    @ObservationIgnored private var stationPausedAt: Date?
    /// Each armed stream item's status, watched so a song that won't load is
    /// reported the moment it fails — see `watch(_:)`.
    @ObservationIgnored private var itemWatches: [ObjectIdentifier: NSKeyValueObservation] = [:]
    /// The Apple `Song`s looked up most recently, by `songKey(for:)`, so a
    /// skip back or a re-arm needs neither the catalog nor the disk. The rest
    /// wait in `AppleSongStore`, which is what lets a track seen before arm
    /// with no network — so songs the Music app has downloaded can start in
    /// airplane mode.
    @ObservationIgnored private var recentSongs: [String: Song] = [:]
    /// About 25 KB each once decoded.
    private static let recentSongLimit = 300
    @ObservationIgnored private var poller: Timer?
    /// What a tap on play/pause asked for, and until when it outranks the
    /// poll. The button flips on the tap; the players catch up a beat later
    /// (MusicKit's `playbackStatus` lags `pause()` noticeably), and a poll
    /// landing in that gap would flip the icon back and then forward again.
    @ObservationIgnored private var requestedPlaying: (playing: Bool, until: Date)?
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
    /// set by a restore, a park or a station taking over in front of the
    /// queue, used by the first arm of that same track, and dropped by
    /// anything that arms a different one.
    @ObservationIgnored private var resumePosition: TimeInterval?
    /// The first row of the run after the armed one, once its Apple songs
    /// have been looked up ahead of the hand-off (see `prepareNextRun()`).
    @ObservationIgnored private var preparedRunStart: Int?
    /// The Apple run after a stream run, already loaded into the Apple player
    /// and prepared while the stream's last song played — see
    /// `prepareNextRun()`. `armApple` only has to press play when the run it
    /// is asked for is still these songs.
    @ObservationIgnored private var preparedAppleRun: (start: Int, songIDs: [MusicItemID])?

    private static let log = Logger(subsystem: "dance.cue", category: "localplayback")
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

    /// Whether this device can play this item: Apple tracks (catalog or
    /// library), Plex or Subsonic tracks that carry their stream URL, and
    /// TuneIn or Apple Music stations — the last in front of the queue
    /// rather than in it (`station`).
    func canPlayLocally(_ item: PlayableContent) -> Bool {
        backendKind(for: item) != nil
    }

    /// A station: no duration, nothing after it, and never a queue row.
    private func isStation(_ item: PlayableContent) -> Bool {
        item.content.type.isRadio
    }

    /// What of `items` can go in the queue: what plays here, bar stations.
    private func queueable(_ items: [PlayableContent]) -> [PlayableContent] {
        items.filter { canPlayLocally($0) && !isStation($0) }
    }

    /// The first station in `items` this device can play.
    private func playableStation(in items: [PlayableContent]) -> PlayableContent? {
        items.first { isStation($0) && canPlayLocally($0) }
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

    /// Every track of a container, page after page, so a long playlist
    /// comes whole — what a download or the watch takes of it.
    func allContainerTracks(for container: PlayableContent) async -> [PlayableContent] {
        var tracks: [PlayableContent] = []
        // Bounded: a source that quietly ignored `offset` would otherwise
        // hand back its first page forever.
        for _ in 0 ..< 200 {
            let page = await containerTracks(for: container, offset: tracks.count)
            guard !page.isEmpty else { break }
            tracks.append(contentsOf: page)
        }
        return tracks
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
    private func appendRemainder(of container: PlayableContent, from start: Int, shuffle: Bool = false, origin: PlayableContent? = nil) async {
        guard start > 0 else { return }
        var offset = start
        // Bounded: a source that quietly ignored `offset` would otherwise
        // append its first page forever.
        for _ in 0 ..< 200 {
            let page = await containerTracks(for: container, offset: offset)
            guard !page.isEmpty else { return }
            offset += page.count
            if isShuffled { unshuffledUpNext?.append(contentsOf: page) }
            try? await addToQueue(shuffle ? page.shuffled() : page, recordingOrder: false)
            setOrigin(origin ?? container, for: page)
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
    ///
    /// A station at `index` plays in front of the queue instead, leaving it
    /// as it was (`playStation(_:)`).
    func play(_ items: [PlayableContent], startingAt index: Int = 0, from position: TimeInterval? = nil) async throws {
        if let item = items[safe: index], let station = playableStation(in: [item]) {
            return try await playStation(station)
        }
        let playable = queueable(items)
        guard !playable.isEmpty else {
            if let station = playableStation(in: items) { return try await playStation(station) }
            throw LocalPlaybackError.nothingPlayable
        }
        // A new queue, so the old origins are gone. `enqueue` names the new
        // one after this returns; a bare list of tracks has none.
        origins = [:]
        queue = playable
        // A new queue is in the order it was given; `enqueue` says otherwise
        // for a shuffled Play.
        isShuffled = false
        unshuffledUpNext = nil
        let start = items[safe: index].flatMap { playable.firstIndex(of: $0) } ?? 0
        // A new queue, so a restored position belongs to nothing in it.
        resumePosition = nil
        try await arm(at: start, from: position)
    }

    /// Inserts `items` right after the current track, in order. Starts
    /// playing if nothing was loaded. While a station plays they go in the
    /// queue behind it, which waits there; a station can't be queued, so one
    /// on its own plays now, as a speaker plays one.
    func playNext(_ items: [PlayableContent]) async throws {
        let playable = queueable(items)
        guard !playable.isEmpty else {
            if let station = playableStation(in: items) { return try await playStation(station) }
            throw LocalPlaybackError.nothingPlayable
        }
        guard isActive else { return try await play(playable) }
        // The armed player owns everything up to `runEnd` and would sail past
        // the insertion straight into its old next track — cut it off after
        // the current one so the run-end advance picks the insert up instead.
        if runEnd > currentIndex {
            truncateArmedRunAfterCurrent()
        }
        queue.insert(contentsOf: playable, at: min(currentIndex + 1, queue.count))
        // Next in the real order too, so shuffle off keeps it next.
        unshuffledUpNext?.insert(contentsOf: playable, at: 0)
    }

    func playNext(_ item: PlayableContent) async throws {
        try await playNext([item])
    }

    /// Appends `items` to the end of the queue (they play when the armed run
    /// ends and the advance reaches them). Starts playing if nothing was
    /// loaded; behind a station they wait in the queue, as `playNext`'s do.
    ///
    /// `recordingOrder: false` is for a caller that has already put the
    /// items in the real order itself — a shuffled page arriving behind a
    /// Shuffle Play, whose real order isn't the order it's queued in.
    func addToQueue(_ items: [PlayableContent], recordingOrder: Bool = true) async throws {
        let playable = queueable(items)
        guard !playable.isEmpty else {
            if let station = playableStation(in: items) { return try await playStation(station) }
            throw LocalPlaybackError.nothingPlayable
        }
        guard isActive else { return try await play(playable) }
        queue.append(contentsOf: playable)
        if recordingOrder { unshuffledUpNext?.append(contentsOf: playable) }
        await extendArmedRun()
    }

    /// Hands rows appended right behind the armed run to the player that is
    /// already playing it, when they're the same service. Otherwise the run
    /// ends where it was armed and the next arm starts a new player for them
    /// — a gap between tracks, and in the background a hand-off the app may
    /// be asleep for (an Apple run) or no longer allowed to start audio for
    /// (a stream run that has let its session go). A Plex album queued in
    /// pages lands this way too, page by page.
    private func extendArmedRun() async {
        // An Apple run fills itself (`fillAppleRun`).
        if backend == .appleMusic {
            fillAppleRun()
            return
        }
        guard let backend, backend != .appleStation,
              repeatMode != .one, !sleepsAtEndOfTrack,
              queue.indices.contains(runEnd), !isStation(queue[runEnd]) else { return }
        var end = runEnd
        while end + 1 < queue.count,
              backendKind(for: queue[end + 1]) == backend,
              !isStation(queue[end + 1]) {
            end += 1
        }
        // A stream run stays a window ahead of the current song; the poll
        // tops it up from there (`topUpStreamRun`).
        if backend == .stream {
            end = min(end, currentIndex + Self.streamWindow)
        }
        guard end > runEnd else { return }
        let token = playToken
        let first = runEnd + 1

        switch backend {
        case .stream:
            guard let player = streamPlayer, player.currentItem != nil else { return }
            for queueIndex in first...end {
                // A song still in iCloud waits for the next arm, which
                // fetches it; so does everything behind it.
                guard let row = queue[safe: queueIndex], cloudPendingURL(for: row) == nil,
                      let url = await streamURL(for: row) else { break }
                // The run moved on (a skip, a re-arm, or it ended) while the
                // URL resolved — whatever arms next picks this row up.
                guard playToken == token, streamPlayer === player, player.currentItem != nil,
                      runEnd == queueIndex - 1 else { return }
                let item = AVPlayerItem(url: url)
                player.insert(item, after: nil)
                register(item, at: queueIndex)
                runEnd = queueIndex
            }
        case .appleMusic, .appleStation:
            break
        }
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
        // A station plays now whatever the position, as a speaker plays one,
        // and in front of the queue rather than in it (`playStation(_:)`).
        if let station = playableStation(in: contents) {
            return try await playStation(station)
        }
        var items: [PlayableContent] = []
        /// `items` before any page was shuffled, for turning shuffle off.
        var unshuffled: [PlayableContent] = []
        /// Where each run of `items` came from: the caller's origin, else a
        /// container stands in for its own tracks.
        var runs: [(origin: PlayableContent?, items: [PlayableContent])] = []
        /// Containers whose first page is in `items`; the rest follows once
        /// playback is underway.
        var containers: [(content: PlayableContent, loaded: Int)] = []
        for content in contents {
            if canPlayLocally(content) {
                items.append(content)
                unshuffled.append(content)
                runs.append((origin, [content]))
            } else if canPlayContainerLocally(content) {
                var page = await containerTracks(for: content, offset: 0)
                unshuffled += page
                if shuffle { page.shuffle() }
                items += page
                runs.append((origin ?? content, page))
                containers.append((content, page.count))
            }
        }
        guard !items.isEmpty else { throw LocalPlaybackError.nothingPlayable }

        switch position {
        case .now, .replace:
            try await play(items)
            // Shuffle Play is shuffle switched on: it can be switched off
            // again, back to the album's order.
            if shuffle {
                isShuffled = true
                var original = unshuffled
                if let current = queue[safe: currentIndex], let index = original.firstIndex(of: current) {
                    original.remove(at: index)
                }
                unshuffledUpNext = original
            }
        case .next, .front: try await playNext(items)
        case .end: try await addToQueue(items)
        }

        // Every run names its own origin, whether it made the queue or was
        // added to one: an album played next inside an artist's run is still
        // that album. `play` cleared the old ones when this replaced them.
        for run in runs {
            setOrigin(run.origin, for: run.items)
        }

        // Playing already, so the tail can arrive behind it.
        guard !containers.isEmpty else { return }
        Task {
            for container in containers {
                await appendRemainder(of: container.content, from: container.loaded, shuffle: shuffle, origin: origin)
            }
        }
    }

    /// Plays `container` from `track` on: a row tapped in an album or
    /// playlist queues the whole list, the way it does on a speaker and in
    /// Music, rather than that one song. The songs before it are in the
    /// queue too, so Previous goes back through them.
    ///
    /// Pages are read until the track turns up — it can sit past the first
    /// page of a long playlist — and the rest follow once it's playing.
    /// Returns `false` when the container can't be played here or the track
    /// isn't in it, so the caller can fall back to the row alone.
    func play(_ track: PlayableContent, in container: PlayableContent) async throws -> Bool {
        guard canPlayContainerLocally(container) else { return false }
        var items: [PlayableContent] = []
        var start: Int?
        // Bounded, like `appendRemainder`: a source that ignored `offset`
        // would hand back its first page forever.
        for _ in 0 ..< 50 {
            let page = await containerTracks(for: container, offset: items.count)
            guard !page.isEmpty else { break }
            if start == nil, let found = page.firstIndex(where: { $0.content.id == track.content.id }) {
                start = items.count + found
            }
            items += page
            if start != nil { break }
        }
        guard let start else { return false }

        try await play(items, startingAt: start)
        setOrigin(container, for: items)
        let loaded = items.count
        Task {
            await appendRemainder(of: container, from: loaded, origin: container)
        }
        return true
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
        // A station has nowhere to seek to, and the queue's spot behind it
        // isn't what's on screen.
        guard station == nil else { return }
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

    /// Jumps to `index` in the queue (e.g. a tap in the Up Next list). Under
    /// a station this goes back to the queue, at its parked spot when it's
    /// the song the queue was left on.
    func play(at index: Int) {
        guard queue.indices.contains(index) else { return }
        Task { try? await arm(at: index) }
    }

    // MARK: - Transport

    func togglePlayback() {
        switch backend {
        case .appleMusic, .appleStation:
            // A tap still inside the last one's window goes by what that tap
            // asked for; the player's own status may not have moved yet.
            let playing = heldPlaying ?? (musicPlayer.state.playbackStatus == .playing)
            if playing {
                musicPlayer.pause()
            } else {
                Task { try? await musicPlayer.play() }
            }
            showRequested(playing: !playing)
        case .stream:
            guard let streamPlayer else { return }
            if streamPlayer.timeControlStatus == .paused {
                // A station paused for a while is rejoined live rather than
                // picked up where it stopped (`liveResumeLimit`).
                if let station, let pausedAt = stationPausedAt,
                   Date.now.timeIntervalSince(pausedAt) > Self.liveResumeLimit {
                    Task { try? await playStation(station) }
                    return
                }
                streamPlayer.play()
                showRequested(playing: true)
            } else {
                streamPlayer.pause()
                notePausedStation()
                showRequested(playing: false)
            }
        case nil:
            // Loaded but nothing armed (e.g. a failed track, a station whose
            // stream dropped) — retry it.
            if let station {
                Task { try? await playStation(station) }
            } else {
                Task { try? await arm(at: currentIndex) }
            }
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
            notePausedStation()
        case nil:
            return
        }
        showRequested(playing: false)
    }

    /// Stamps when a station's stream was paused, at the pause itself: the
    /// poll does it too, but may not run before the app is suspended
    /// (`liveResumeLimit`).
    private func notePausedStation() {
        guard station != nil, stationPausedAt == nil else { return }
        stationPausedAt = .now
    }

    /// Flips the button now rather than on the next poll, and holds it there
    /// while the player catches up.
    private func showRequested(playing: Bool) {
        requestedPlaying = (playing, Date.now.addingTimeInterval(1.5))
        if isPlaying != playing { isPlaying = playing }
    }

    /// The requested state while it still outranks the poll.
    private var heldPlaying: Bool? {
        guard let requestedPlaying, requestedPlaying.until > .now else { return nil }
        return requestedPlaying.playing
    }

    /// The polled state, unless a tap's request still holds and the player
    /// hasn't caught up to it — then the request. Clears the hold once the
    /// player agrees, so a later change (an interruption, the other end of
    /// AirPlay) isn't masked.
    private func reconcilePlaying(_ polled: Bool) -> Bool {
        guard let held = heldPlaying else {
            requestedPlaying = nil
            return polled
        }
        if held == polled { requestedPlaying = nil }
        return held
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

    /// Turns shuffle on — Up Next in a random order — or off, back to the
    /// order it had before. Songs added while shuffled keep their places
    /// after the ones that were already there.
    func setShuffle(_ on: Bool) {
        guard on != isShuffled else { return }
        let start = currentIndex + 1
        if on {
            isShuffled = true
            unshuffledUpNext = start < queue.count ? Array(queue[start...]) : []
            shuffleUpNext()
            return
        }
        isShuffled = false
        let original = unshuffledUpNext ?? []
        unshuffledUpNext = nil
        guard start < queue.count, !original.isEmpty else { return }
        if runEnd > currentIndex {
            truncateArmedRunAfterCurrent()
        }
        var remaining = Array(queue[start...])
        var restored: [PlayableContent] = []
        for item in original {
            if let index = remaining.firstIndex(of: item) {
                restored.append(remaining.remove(at: index))
            }
        }
        queue.replaceSubrange(start..., with: restored + remaining)
    }

    /// Reorders what follows the current track at random. The current track
    /// keeps playing; the run is cut off after it so the new order takes
    /// effect at the next track boundary.
    private func shuffleUpNext() {
        let start = currentIndex + 1
        guard start + 1 < queue.count else { return }
        if runEnd > currentIndex {
            truncateArmedRunAfterCurrent()
        }
        queue[start...].shuffle()
    }

    /// Drops everything after the current track. The current track plays on
    /// and playback stops when it ends (or loops it, under Repeat).
    func clearUpNext() {
        let start = currentIndex + 1
        guard start < queue.count else { return }
        if runEnd > currentIndex {
            truncateArmedRunAfterCurrent()
        }
        queue.removeSubrange(start...)
        if isShuffled { unshuffledUpNext = [] }
    }

    /// Removes queue rows after the current track. Played rows and the
    /// current one stay: the armed run maps player entries to queue indices
    /// up to the current track, and moving those would point it at the
    /// wrong rows.
    func removeFromQueue(at indices: IndexSet) {
        let upcoming = indices.filter { $0 > currentIndex && $0 < queue.count }
        guard !upcoming.isEmpty else { return }
        if runEnd > currentIndex {
            truncateArmedRunAfterCurrent()
        }
        var updated = queue
        for index in upcoming.sorted(by: >) {
            let removed = updated.remove(at: index)
            if let saved = unshuffledUpNext?.firstIndex(of: removed) {
                unshuffledUpNext?.remove(at: saved)
            }
        }
        queue = updated
    }

    /// Reorders rows after the current track. Offsets are queue indices, in
    /// the shape `onMove` hands them over; a move into or above the current
    /// track lands just after it.
    func moveInQueue(from source: IndexSet, to destination: Int) {
        let start = currentIndex + 1
        let upcoming = source.filter { $0 >= start && $0 < queue.count }
        guard !upcoming.isEmpty else { return }
        if runEnd > currentIndex {
            truncateArmedRunAfterCurrent()
        }
        // `onMove`'s destination counts the moved rows still in place, so
        // the insertion point shifts up by those taken from above it.
        let target = min(max(destination, start), queue.count)
        let moved = upcoming.sorted().map { queue[$0] }
        var updated = queue
        for index in upcoming.sorted(by: >) {
            updated.remove(at: index)
        }
        let insertAt = target - upcoming.filter { $0 < target }.count
        updated.insert(contentsOf: moved, at: insertAt)
        queue = updated
    }

    /// Moves an upcoming row to play right after the current track.
    func moveToNext(at index: Int) {
        guard index > currentIndex + 1, index < queue.count else { return }
        moveInQueue(from: [index], to: currentIndex + 1)
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
        // An Apple station skips to its own next song, not past itself into
        // the queue; a live one, or a TuneIn stream, has nothing to skip to.
        if let station {
            guard isPlayingAppleStation else { return }
            // Stopped, or still arming: Next starts it, which is a new song.
            guard backend == .appleStation else {
                Task { try? await playStation(station) }
                return
            }
            Task {
                do {
                    try await musicPlayer.skipToNextEntry()
                } catch {
                    AlertService.shared.showAlert(with: "Couldn't skip this song", imageName: "exclamationmark.triangle")
                }
            }
            return
        }
        let target = (armingIndex ?? currentIndex) + 1
        guard target < queue.count else {
            if repeatMode == .all, !queue.isEmpty {
                Task { try? await arm(at: 0) }
            } else {
                rewindToStart()
            }
            return
        }
        // Inside the armed run the native skip is instant (and keeps the run's
        // gapless chain); past its end we arm the next run ourselves.
        if armingIndex == nil, target <= runEnd, let backend {
            switch backend {
            case .appleMusic:
                Task { try? await musicPlayer.skipToNextEntry() }
                if let following = appleRun.first(where: { $0.queueIndex > currentIndex }) {
                    showAppleSkip(to: following)
                }
            case .stream:
                streamPlayer?.advanceToNextItem()
                followStreamPlayer()
            case .appleStation:
                // Only ever in front of the queue, and skipped above.
                break
            }
        } else {
            Task { try? await arm(at: target) }
        }
    }

    /// Moves the queue's place to the song the stream player is on now,
    /// without waiting for the poll: a skip shows its song at once, and a
    /// press made straight after it goes from there. The poll fills in the
    /// rest (the item's own length, its audio quality).
    private func followStreamPlayer() {
        guard let item = streamPlayer?.currentItem,
              let queueIndex = streamRun[ObjectIdentifier(item)],
              queueIndex != currentIndex else { return }
        currentIndex = queueIndex
        progress = 0
        duration = catalogDuration(at: queueIndex)
        topUpStreamRun()
    }

    /// Keeps a stream run's window ahead of playback: once it's down to a
    /// few songs after the current one, the next ones are handed to the
    /// player that's playing. Synchronous, so a run of quick skips can't
    /// outpace it — a track's URL needs no network.
    private func topUpStreamRun() {
        // A station's player holds the station alone; the queue waits.
        guard backend == .stream, station == nil, let player = streamPlayer, player.currentItem != nil,
              repeatMode != .one, !sleepsAtEndOfTrack,
              runEnd - currentIndex < Self.streamTopUpThreshold else { return }
        let limit = min(queue.count - 1, currentIndex + Self.streamWindow)
        guard runEnd < limit else { return }
        for queueIndex in (runEnd + 1)...limit {
            let row = queue[queueIndex]
            // The run ends at another service or a song still in iCloud; the
            // run-end advance arms those.
            guard backendKind(for: row) == .stream, !isStation(row),
                  cloudPendingURL(for: row) == nil,
                  let url = trackStreamURL(for: row) else { return }
            let item = AVPlayerItem(url: url)
            player.insert(item, after: nil)
            register(item, at: queueIndex)
            runEnd = queueIndex
        }
    }

    func previous() {
        // A station has nothing before it to go back to.
        guard station == nil else { return }
        // Mid-arm, back from where that arm is going (see `armingIndex`).
        if let armingIndex {
            if armingIndex > 0 { Task { try? await arm(at: armingIndex - 1) } }
            return
        }
        // First tap restarts the track, a quick second tap goes back — the
        // same rule every player uses.
        if progress > 3 || currentIndex == 0 {
            restartCurrent()
        } else if backend == .appleMusic, let entry = appleEntry(before: currentIndex) {
            // Still in the Apple player's queue, so it steps back there —
            // a re-arm loads the whole queue again.
            Task { try? await musicPlayer.skipToPreviousEntry() }
            showAppleSkip(to: entry)
        } else {
            Task { try? await arm(at: currentIndex - 1) }
        }
    }

    /// The Apple player's entry before the one for queue row `index`, if it
    /// has one.
    private func appleEntry(before index: Int) -> AppleRunEntry? {
        guard let offset = appleRun.firstIndex(where: { $0.queueIndex == index }), offset > 0 else { return nil }
        return appleRun[offset - 1]
    }

    /// Shows an Apple skip at once rather than on a poll after the player
    /// gets there (see `appleSkipHold`), so a run of presses counts from
    /// where the last one showed.
    private func showAppleSkip(to entry: AppleRunEntry) {
        appleSkipHold = (entry.queueIndex, .now.addingTimeInterval(3))
        currentIndex = entry.queueIndex
        progress = 0
        duration = entry.duration ?? catalogDuration(at: entry.queueIndex)
    }

    func stop() {
        poller?.invalidate()
        poller = nil
        cancelSleepTimer()
        preparedAppleRun = nil
        teardownRun()
        resumePosition = nil
        station = nil
        isShuffled = false
        unshuffledUpNext = nil
        queue = []
        origins = [:]
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
        // cutoff a restore and a route switch use. A station's time isn't
        // the queue's: the spot the queue was left at stands.
        if station == nil {
            resumePosition = position > 2 ? position : nil
        }
        savePosition()
    }

    /// Arms the current track again and plays it, from the parked spot when
    /// there is one — the undo of `park()`, for a hand-off the speaker
    /// refused. `play(_:)` would replace the queue; this keeps it. A station
    /// that was playing in front of the queue plays again instead.
    func resumeCurrent() async throws {
        guard isActive else { return }
        if let station {
            try await playStation(station)
        } else {
            try await arm(at: currentIndex)
        }
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

    // MARK: - Stations

    /// Plays `station` in front of the queue. The queue isn't touched: its
    /// run is taken down and it waits behind the station on the song it
    /// was on, with the spot in that song kept for going back to it (see
    /// `station`). A station already playing hands over to this one and
    /// the queue's spot stays as it was.
    func playStation(_ station: PlayableContent) async throws {
        guard isStation(station), let kind = backendKind(for: station) else {
            throw LocalPlaybackError.nothingPlayable
        }
        playToken += 1
        let token = playToken
        armingIndex = nil
        // An Apple run loaded ahead of a hand-off is about to be replaced by
        // this station in the Apple player; armed later, it would play the
        // station's queue as those songs.
        preparedAppleRun = nil
        // What to fall back to if this one won't play.
        let previousStation = self.station
        // The queue's spot, read before the teardown, as `park()` does: the
        // poll's last tick is what's there.
        if self.station == nil, !queue.isEmpty {
            let position = progress
            resumePosition = position > 2 ? position : nil
            savePosition()
        }
        // Straight on from a stream player, as `arm(at:)` does.
        let keepsAudioSession = kind == .stream
        teardownRun(keepingAudioSession: keepsAudioSession)
        defer {
            if keepsAudioSession, playToken == token, backend != .stream {
                releaseAudioSession()
            }
        }
        self.station = station
        progress = 0
        duration = 0
        startPolling()
        do {
            switch kind {
            case .stream:
                try await armStationStream(station, token: token)
            case .appleStation:
                try await armAppleStation(station, token: token)
            case .appleMusic:
                throw LocalPlaybackError.nothingPlayable
            }
        } catch {
            // Back to what was there, paused: the station before it, ready to
            // play again, or the queue as it was left. A station that won't
            // play shouldn't stand in front of either.
            if playToken == token {
                self.station = previousStation
                isPlaying = false
                if previousStation == nil {
                    duration = catalogDuration(at: currentIndex)
                    progress = resumePosition ?? 0
                }
            }
            throw error
        }
    }

    /// The station's stream ended or dropped, or the Apple player gave it
    /// up: paused on the station with nothing armed, and Play starts it
    /// again (`togglePlayback`).
    private func stationStopped() {
        poller?.invalidate()
        poller = nil
        teardownRun()
        isPlaying = false
        isLoading = false
        progress = 0
    }

    /// How long a TuneIn station can stand paused and still pick up from
    /// where it stopped. Past this, Play starts it again: a live stream
    /// can't be resumed, only rejoined (iOS draws its pause as a stop for
    /// that reason), and a stream left paused for long has usually been
    /// dropped by its server, so the old item would fail or play stale
    /// audio.
    private static let liveResumeLimit: TimeInterval = 30

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

    /// The last index of the contiguous same-backend run starting at `index`,
    /// looking no further than an arm takes (`armSpan` rows): a run's player
    /// starts with a window of it and the rest follows, so scanning to the
    /// end of a 1,700-song run on every arm and skip was work thrown away.
    /// A station never joins a run: it plays in front of the queue, never in
    /// it (`playStation(_:)`).
    private func runEnd(from index: Int) -> Int {
        guard let kind = backendKind(for: queue[index]), !isStation(queue[index]) else { return index }
        let limit = min(queue.count - 1, index + Self.armSpan - 1)
        var end = index
        while end < limit,
              backendKind(for: queue[end + 1]) == kind,
              !isStation(queue[end + 1]) {
            end += 1
        }
        return end
    }

    /// The most rows an arm hands its player to start with.
    private static let armSpan = max(streamWindow, appleWindow)

    /// Hands the run starting at `index` to its native player and starts it.
    ///
    /// `position` starts the track that many seconds in. Without it, the
    /// saved position is for the track that was current when the app last
    /// ran: this arm takes it if that is the track, and any other arm drops
    /// it, so a tap on another row can't land partway into it.
    private func arm(at index: Int, from position: TimeInterval? = nil) async throws {
        playToken += 1
        let token = playToken
        armingIndex = index
        defer { if playToken == token { armingIndex = nil } }
        // Straight back to a stream player: the audio session stays ours.
        // Letting it go and taking it back on every Previous or long skip
        // was a round trip to the audio server each way, and told other
        // apps they could resume for the moment in between.
        let keepsAudioSession = queue.indices.contains(index) && backendKind(for: queue[index]) == .stream
        teardownRun(keepingAudioSession: keepsAudioSession)
        // Unless nothing ended up playing on it.
        defer {
            if keepsAudioSession, playToken == token, backend != .stream {
                releaseAudioSession()
            }
        }
        guard queue.indices.contains(index) else {
            stop()
            return
        }
        // Back to the queue: a station in front of it is put away, and the
        // spot it kept for the song the queue was on is picked up below.
        if station != nil { station = nil }
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
        case .appleStation, nil:
            // Shouldn't happen — the queue only takes playable items, and
            // never a station (`queueable`).
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

    /// Where playback is at `date`, not where the player was last read: the
    /// clock's setting run forward while playing, clamped to the song's
    /// length. Live streams have no length to stop at.
    func estimatedProgress(at date: Date = .now) -> TimeInterval {
        isPlaying ? runningProgress(at: date) : progressAnchor
    }

    private func runningProgress(at date: Date) -> TimeInterval {
        guard progressAnchoredAt != .distantPast else { return progressAnchor }
        let elapsed = progressAnchor + max(date.timeIntervalSince(progressAnchoredAt), 0)
        return duration > 0 ? min(elapsed, duration) : elapsed
    }

    /// Records a reading of the player's clock from the poll.
    ///
    /// While playing, a reading within `progressTolerance` of the estimate is
    /// dropped: the clock already has it, and taking it would invalidate every
    /// progress display twice a second for nothing. Anything further off is
    /// the player being somewhere else — a stall, a seek from Control Center
    /// or the car, the next song — and is taken. Paused, a reading is written
    /// only when it changed.
    private func noteProgress(_ reading: TimeInterval) {
        if isPlaying {
            guard abs(reading - runningProgress(at: .now)) >= Self.progressTolerance else { return }
        } else {
            guard reading != progressAnchor else { return }
        }
        progress = reading
    }

    /// How far the player's clock can sit from the estimate before it's worth
    /// a write. The player reports its time exactly, so this only has to
    /// cover the moment between Play and the audio starting.
    private static let progressTolerance: TimeInterval = 0.5

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
                rewindToStart()
            }
            return
        }
        Task { try? await arm(at: end + 1) }
    }

    /// The queue has played out with nothing set to repeat: back to its first
    /// song, paused at the start, with nothing armed — the way a finished
    /// album waits in Music. Play starts it again from the top. Clearing it
    /// instead left the player on "Nothing Playing", with what was queued
    /// gone.
    private func rewindToStart() {
        guard !queue.isEmpty else {
            stop()
            return
        }
        // Supersedes an arm still in flight (a Next pressed through to the
        // end while one was loading), which would otherwise start playing
        // after this.
        playToken += 1
        armingIndex = nil
        poller?.invalidate()
        poller = nil
        cancelSleepTimer()
        teardownRun()
        resumePosition = nil
        currentIndex = 0
        isPlaying = false
        isLoading = false
        progress = 0
        // Parked on the first song: show its length, as a paused speaker
        // would, rather than no scrubber at all.
        duration = catalogDuration(at: 0)
        savePosition()
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

    /// How long before the end of a song the player is left to line up the
    /// next one undisturbed, and the next run's songs are looked up.
    private static let joinLeadTime: TimeInterval = 15

    /// A stream player item played to its end. When it was the run's last,
    /// the run is over: arm what follows now. Earlier items are the player
    /// advancing within its run, which it does itself.
    private func streamItemDidFinish(_ item: ObjectIdentifier) {
        guard backend == .stream, streamPlayer != nil,
              let queueIndex = streamRun[item], queueIndex == runEnd else { return }
        let end = runEnd
        teardownRun()
        advancePastRun(endingAt: end)
    }

    /// Looks up the next run's Apple songs while the last song of this run
    /// plays, so the hand-off at its end arms from the cache instead of
    /// waiting on the catalog — the difference between a beat of silence
    /// and a couple of seconds of it. Once per run; streams need nothing
    /// ahead, since the playback cache already fetches the songs coming up.
    private func prepareNextRun() {
        let next = runEnd + 1
        guard backend != nil, currentIndex == runEnd, preparedRunStart != next,
              repeatMode != .one, !sleepsAtEndOfTrack,
              queue.indices.contains(next), backendKind(for: queue[next]) == .appleMusic,
              duration > 0, duration - progress < Self.joinLeadTime else { return }
        preparedRunStart = next
        // The rows `armApple` will start that run with, so it finds them
        // prepared.
        let end = Self.appleWindowEnd(from: next, through: runEnd(from: next))
        Self.log.notice("looking ahead to the run at \(next)...\(end)")
        let fromStream = backend == .stream
        let token = playToken
        Task {
            guard let resolved = try? await resolveAppleSongs(next...end) else {
                Self.log.notice("pre-arm: resolving the Apple run at \(next) failed")
                return
            }
            // Coming off a stream, the Apple player is idle: load and
            // prepare the run now, so the hand-off is a press of play rather
            // than a queue load and a prepare in silence, which was most of
            // the gap between a Plex song and an Apple one. Off an Apple run
            // the player is busy playing, so the songs alone will do.
            guard fromStream, !resolved.isEmpty,
                  playToken == token, backend == .stream, runEnd + 1 == next else {
                Self.log.notice("pre-arm skipped: fromStream=\(fromStream) resolved=\(resolved.count) tokenSame=\(self.playToken == token) stream=\(self.backend == .stream) runEnd=\(self.runEnd) next=\(next)")
                return
            }
            musicPlayer.queue = ApplicationMusicPlayer.Queue(for: resolved.map(\.song))
            do {
                try await musicPlayer.prepareToPlay()
            } catch {
                Self.log.error("pre-arming the Apple run failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard playToken == token, backend == .stream, runEnd + 1 == next else { return }
            preparedAppleRun = (next, resolved.map(\.song.id))
            Self.log.notice("Apple run at \(next) prepared ahead of the hand-off")
        }
    }

    /// Silences whichever player is armed. Sets `backend` to nil first so the
    /// poll can't misread the teardown as a run ending.
    private func teardownRun(keepingAudioSession: Bool = false) {
        let previous = backend
        // The stream run is ending into an Apple run that's already loaded:
        // keep the audio session rather than release it and take it straight
        // back, which only adds to the gap.
        let handsToPreparedApple = previous == .stream && preparedAppleRun?.start == runEnd + 1
        backend = nil
        // Whatever was playing has been left, wherever it got to.
        PlayReporter.shared.end()
        runEnd = -1
        preparedRunStart = nil
        appleRun = []
        appleFill?.task.cancel()
        appleFill = nil
        appleSkipHold = nil
        appleWasPlaying = false
        appleRunExpectedEnd = nil
        requestedPlaying = nil
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
            stationItem = nil
            stationPausedAt = nil
            itemWatches = [:]
            nowPlayingCard.end()
            isPlayingLocalStream = false
            if !handsToPreparedApple, !keepingAudioSession {
                releaseAudioSession()
            }
        }
    }

    /// Hands the audio session back to whatever held it behind us (see
    /// `AudioSessionArbiter`), otherwise releases it entirely.
    private func releaseAudioSession() {
        if !AudioSessionArbiter.shared.handBack() {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
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
                // The entries map in step with the player's, or what the
                // fill adds next would be read as the rows cut off.
                let kept = entries.distance(from: entries.startIndex, to: after)
                if appleRun.count > kept {
                    appleRun.removeSubrange(kept...)
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
        // Taken either way: it was for this hand-off and no other.
        let prepared = preparedAppleRun
        preparedAppleRun = nil

        // The first songs only; the rest follow once they're playing.
        let windowEnd = Self.appleWindowEnd(from: index, through: end)
        let resolved = try await resolveAppleSongs(index...windowEnd)

        // The user skipped elsewhere while we were resolving — that call owns
        // playback now.
        guard playToken == token else { return }
        guard let first = resolved.first else {
            // Nothing in these rows resolved (e.g. region-unavailable tracks) —
            // a lone track is an error worth surfacing, otherwise skip on.
            if windowEnd + 1 < queue.count {
                advancePastRun(endingAt: windowEnd)
                return
            }
            throw LocalPlaybackError.songNotFound
        }

        // Already loaded and prepared during the last stream song, if the run
        // is still those songs — a queue edit or a skip since then and it's
        // loaded again here.
        let isPrepared = resume == nil
            && prepared?.start == index
            && prepared?.songIDs == resolved.map(\.song.id)
        Self.log.notice("arming Apple run at \(index), prepared=\(isPrepared)")
        if !isPrepared {
            // It starts at its first song either way. Naming it as the start
            // item made the player refuse some catalog songs outright ("Prepare
            // queue failed with unexpected start item"), so a playlist that
            // opened with one never played.
            musicPlayer.queue = ApplicationMusicPlayer.Queue(for: resolved.map(\.song))
        }
        if !isPrepared, let resume, resume > 0 {
            // Point the player partway in before it starts. A seek issued
            // after `play()` returns is dropped while the entry is still
            // preparing, which started a hand-off's track from the top.
            try await musicPlayer.prepareToPlay()
            guard playToken == token else { return }
            musicPlayer.playbackTime = resume
        }
        try await musicPlayer.play()
        guard playToken == token else { return }

        appleRun = resolved.map(AppleRunEntry.init)
        backend = .appleMusic
        runEnd = windowEnd
        currentIndex = first.queueIndex
        duration = first.song.duration ?? catalogDuration(at: first.queueIndex)
        fillAppleRun()
    }

    /// The last row an Apple run starting at `index` is armed with: the
    /// first `appleWindow` rows of the run ending at `end`.
    private static func appleWindowEnd(from index: Int, through end: Int) -> Int {
        min(end, index + appleWindow - 1)
    }

    /// Keeps the Apple player's queue `appleQueueAhead` songs past the one
    /// playing: the Apple rows after the armed run are looked up and handed
    /// to the player in one insert while it plays. Started by an arm, by
    /// rows added behind the run, and by the poll once the songs queued
    /// ahead are down to half.
    private func fillAppleRun() {
        guard backend == .appleMusic, appleFill == nil,
              repeatMode != .one, !sleepsAtEndOfTrack,
              runEnd - currentIndex < Self.appleQueueAhead / 2,
              Date.now >= appleFillRetryAfter,
              let row = queue[safe: runEnd + 1],
              backendKind(for: row) == .appleMusic, !isStation(row) else { return }
        let token = playToken
        let task = Task { [weak self] in
            // Cue is suspended soon after the phone locks while Apple's
            // player plays on: ask for the time to finish, so a lock straight
            // after Play doesn't leave the run at its first songs.
            var background = UIBackgroundTaskIdentifier.invalid
            background = UIApplication.shared.beginBackgroundTask(withName: "Queue Apple Music") {
                UIApplication.shared.endBackgroundTask(background)
                background = .invalid
            }
            while let self, await self.appendToAppleRun(token: token) {}
            if background != .invalid {
                UIApplication.shared.endBackgroundTask(background)
            }
            if self?.appleFill?.token == token { self?.appleFill = nil }
        }
        appleFill = (token, task)
    }

    /// Looks up the Apple rows after the armed run, as far as
    /// `appleQueueAhead`, and hands them to the player. False once there's
    /// nothing more to add for now, or the run has moved on.
    private func appendToAppleRun(token: Int) async -> Bool {
        guard !Task.isCancelled, playToken == token, backend == .appleMusic,
              repeatMode != .one, !sleepsAtEndOfTrack,
              // A finished or paused queue is left to the run-end advance,
              // which arms these rows itself.
              musicPlayer.state.playbackStatus == .playing else { return false }
        let first = runEnd + 1
        let limit = currentIndex + Self.appleQueueAhead
        var last = first - 1
        while last < limit, let row = queue[safe: last + 1],
              backendKind(for: row) == .appleMusic, !isStation(row) {
            last += 1
        }
        guard last >= first else { return false }
        // Whether the rows are still where they were looked up, right after
        // the run: a Play Next, a reorder or Repeat One can land meanwhile.
        let ids = queue[first...last].map(\.id)
        let unchanged = { [unowned self] in
            runEnd == first - 1 && last < queue.count && queue[first...last].map(\.id) == ids
        }

        let resolved: [(queueIndex: Int, song: Song)]
        do {
            resolved = try await resolveAppleSongs(first...last)
        } catch {
            appleFillRetryAfter = .now.addingTimeInterval(30)
            return false
        }
        guard !Task.isCancelled, playToken == token, backend == .appleMusic else { return false }
        // Start again from the queue as it is now.
        guard unchanged() else { return true }
        if !resolved.isEmpty {
            let wait = Self.appleInsertSpacing - Date.now.timeIntervalSince(lastAppleInsert)
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled, playToken == token, backend == .appleMusic else { return false }
                guard unchanged() else { return true }
            }
            lastAppleInsert = .now
            do {
                try await musicPlayer.queue.insert(resolved.map(\.song), position: .tail)
            } catch {
                Self.log.error("adding songs to the Apple queue failed: \(error.localizedDescription, privacy: .public)")
                appleFillRetryAfter = .now.addingTimeInterval(30)
                return false
            }
            guard playToken == token, backend == .appleMusic else { return false }
            // Cut off or rearranged while the insert was in flight: cut again
            // so what just landed goes too, and carry on from there.
            guard unchanged() else {
                truncateArmedRunAfterCurrent()
                return true
            }
            appleRun += resolved.map(AppleRunEntry.init)
            // The old last entry isn't the last any more; the new one sets
            // its own end time once it plays.
            appleRunExpectedEnd = nil
        }
        // Rows that didn't resolve are stepped over with the rest.
        runEnd = last
        return true
    }

    /// Resolves the Apple rows in `rows` into `Song`s, keeping track of which
    /// queue rows made it — a failed row is skipped, not fatal to the run.
    ///
    /// Each song comes from the first place that has it: the songs looked up
    /// lately, the store on disk, the library (library rows, a request per
    /// hundred), then the catalog (likewise).
    private func resolveAppleSongs(_ rows: ClosedRange<Int>) async throws -> [(queueIndex: Int, song: Song)] {
        let items = rows.compactMap { index in queue[safe: index].map { (queueIndex: index, item: $0) } }
        let keys = Set(items.map { Self.songKey(for: $0.item) })
        var songs: [String: Song] = [:]
        for key in keys {
            songs[key] = recentSongs[key]
        }
        let unseen = keys.subtracting(songs.keys)
        if !unseen.isEmpty {
            let stored = await AppleSongStore.shared.songs(for: Array(unseen))
            songs.merge(stored) { current, _ in current }
            remember(stored)
        }

        var found: [String: Song] = [:]
        // Library tracks resolve from the library itself. Going through the
        // catalog first was why playing one sometimes did nothing: a
        // library-only track — a matched upload, or a purchase Apple Music
        // doesn't carry — has no catalog equivalent.
        let libraryIDs = Set(items.lazy
            .filter { $0.item.content.type == .libraryTrack && songs[Self.songKey(for: $0.item)] == nil }
            .map(\.item.content.id))
        for (id, song) in await librarySongs(ids: Array(libraryIDs)) {
            found[Self.libraryCacheKey(for: id)] = song
        }
        // The rest from the catalog. A library track the library no longer
        // has goes by its catalog twin, and is kept under its library id so
        // the next arm finds it without the lookup.
        var catalogRows: [String: String] = [:]
        var unmapped: Set<String> = []
        for (_, item) in items {
            let key = Self.songKey(for: item)
            guard songs[key] == nil, found[key] == nil else { continue }
            if item.content.type == .libraryTrack {
                unmapped.insert(item.content.id)
            } else {
                catalogRows[key] = item.content.id
            }
        }
        for (libraryID, catalogID) in await catalogIDs(forLibraryIDs: Array(unmapped)) {
            catalogRows[Self.libraryCacheKey(for: libraryID)] = catalogID
        }
        if !catalogRows.isEmpty {
            let fetched = try await MusicSearchService.shared.appleSongs(ids: Array(Set(catalogRows.values)))
            let byID = Dictionary(fetched.map { ($0.id.rawValue, $0) }, uniquingKeysWith: { first, _ in first })
            for (key, catalogID) in catalogRows {
                found[key] = byID[catalogID]
            }
        }
        if !found.isEmpty {
            songs.merge(found) { current, _ in current }
            remember(found)
            Task.detached(priority: .utility) {
                await AppleSongStore.shared.store(found)
            }
        }
        return items.compactMap { row in
            songs[Self.songKey(for: row.item)].map { (row.queueIndex, $0) }
        }
    }

    /// Keeps `found` among the songs looked up lately, dropping the lot once
    /// there are too many — the store on disk still has them.
    private func remember(_ found: [String: Song]) {
        guard !found.isEmpty else { return }
        if recentSongs.count + found.count > Self.recentSongLimit {
            recentSongs.removeAll(keepingCapacity: true)
        }
        recentSongs.merge(found) { _, new in new }
    }

    /// Hands an Apple Music station to the Apple player, in front of the
    /// queue (`playStation(_:)`). Stations are `PlayableMusicItem`s in their
    /// own right, so no song resolution — the player runs the station's
    /// stream of tracks itself.
    ///
    /// `runEnd` stays at -1, short of every queue row: nothing of the queue
    /// is in this player, so nothing that edits the queue behind the station
    /// reaches into it, and nothing tops it up from there.
    private func armAppleStation(_ item: PlayableContent, token: Int) async throws {
        isLoading = true
        defer { if playToken == token { isLoading = false } }

        let request = MusicCatalogResourceRequest<Station>(matching: \.id, equalTo: MusicItemID(item.content.id))
        guard let station = try? await request.response().items.first else {
            // Only worth saying if nothing else has been played meanwhile.
            guard playToken == token else { return }
            throw LocalPlaybackError.stationNotFound
        }
        guard playToken == token else { return }

        musicPlayer.queue = ApplicationMusicPlayer.Queue(for: [station])
        try await musicPlayer.play()
        guard playToken == token else { return }

        appleRun = []
        backend = .appleStation
        runEnd = -1
        duration = 0
    }

    /// Cache key for a library `Song`. Namespaced so a library id can't collide
    /// with the catalog ids the rest of the cache holds.
    private static func libraryCacheKey(for id: String) -> String { "library:\(id)" }

    /// What a row's `Song` is kept under.
    private static func songKey(for item: PlayableContent) -> String {
        item.content.type == .libraryTrack ? libraryCacheKey(for: item.content.id) : item.content.id
    }

    /// Library `Song`s for library-track rows, by library id, queued directly
    /// rather than via their catalog twins — `ApplicationMusicPlayer` plays
    /// library items, and this is the only path that works for a track the
    /// catalog doesn't have. A request per hundred: one per song took eight
    /// seconds for 600.
    private func librarySongs(ids: [String]) async -> [String: Song] {
        var found: [String: Song] = [:]
        for start in stride(from: 0, to: ids.count, by: 100) {
            let chunk = ids[start..<min(start + 100, ids.count)]
            var request = MusicLibraryRequest<Song>()
            request.filter(matching: \.id, memberOf: chunk.map { MusicItemID($0) })
            request.limit = chunk.count
            guard let songs = try? await request.response().items else { continue }
            for song in songs {
                found[song.id.rawValue] = song
            }
        }
        return found
    }

    /// The Apple Music catalog ids of library tracks, by library id, for
    /// those the library request didn't return. An `a.` id — a catalog song
    /// in a library playlist, not in the library itself — is its catalog id
    /// with a prefix. Others (`i.…`) are mapped through the web API — the
    /// same way radio seeding does — a few at a time.
    private func catalogIDs(forLibraryIDs ids: [String]) async -> [String: String] {
        var found: [String: String] = [:]
        var unmapped: [String] = []
        for id in ids {
            let suffix = id.dropFirst(2)
            if id.hasPrefix("a."), !suffix.isEmpty, suffix.allSatisfy(\.isNumber) {
                found[id] = String(suffix)
            } else {
                unmapped.append(id)
            }
        }
        guard !unmapped.isEmpty else { return found }
        let lookUp: @Sendable (String) async -> (String, String?) = { id in
            (id, await MusicSearchService.shared.appleLibraryLookup(id: id)?.data.first?.id)
        }
        return await withTaskGroup(of: (String, String?).self) { group in
            var pending = unmapped[...]
            for id in pending.prefix(6) {
                group.addTask { await lookUp(id) }
            }
            pending = pending.dropFirst(6)
            while let (id, catalogID) = await group.next() {
                found[id] = catalogID
                if let next = pending.popFirst() {
                    group.addTask { await lookUp(next) }
                }
            }
            return found
        }
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
            // The player starts buffering the next song well before the
            // current one ends, so it can join them without a gap. Swapping
            // it out that close to the join throws the buffer away and
            // opens the gap; the stream is already on its way by then.
            if queueIndex == currentIndex + 1, duration > 0, duration - progress < Self.joinLeadTime {
                return
            }
            let replacement = AVPlayerItem(url: url)
            guard streamPlayer.canInsert(replacement, after: playerItem) else { return }
            streamPlayer.insert(replacement, after: playerItem)
            streamPlayer.remove(playerItem)
            streamRun[ObjectIdentifier(playerItem)] = nil
            itemWatches[ObjectIdentifier(playerItem)] = nil
            register(replacement, at: queueIndex)
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
        return trackStreamURL(for: item)
    }

    /// Hands `item` to the armed stream run as queue row `queueIndex`.
    private func register(_ item: AVPlayerItem, at queueIndex: Int) {
        streamRun[ObjectIdentifier(item)] = queueIndex
        watch(item)
    }

    /// Reports a song that won't load as soon as it fails. `AVQueuePlayer`
    /// drops a failed item and moves on by itself, often before the next
    /// poll — and when it was the last one the queue looked finished, so a
    /// song that couldn't play just sat at 0:00 with no word why.
    private func watch(_ item: AVPlayerItem) {
        itemWatches[ObjectIdentifier(item)] = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.streamItemFailed(item) }
        }
    }

    private func streamItemFailed(_ item: AVPlayerItem) {
        let key = ObjectIdentifier(item)
        let row = key == stationItem ? station : streamRun[key].flatMap { queue[safe: $0] }
        guard itemWatches.removeValue(forKey: key) != nil, let row else { return }
        AlertService.shared.showAlert(with: "Couldn't play “\(row.title)”", imageName: "exclamationmark.triangle")
        // The item's error and the stream's path (not its query, which
        // carries the server's token).
        let error = item.error as NSError?
        let underlying = error?.userInfo[NSUnderlyingErrorKey] as? NSError
        let path = (item.asset as? AVURLAsset)?.url.path ?? "?"
        Self.log.error("couldn't play \(row.title, privacy: .public) [\(row.metadata?.audioCodec ?? "?", privacy: .public)] from \(path, privacy: .public): \(error?.domain ?? "", privacy: .public) \(error?.code ?? 0) \(error?.localizedDescription ?? "", privacy: .public) / \(underlying?.domain ?? "", privacy: .public) \(underlying?.code ?? 0) \(underlying?.localizedDescription ?? "", privacy: .public)")
    }

    /// `streamURL(for:)` for anything but a station: answered at once.
    private func trackStreamURL(for item: PlayableContent) -> URL? {
        // A local copy beats the server URL. The server URL is built now,
        // not read off the item, so the Streaming Quality setting in force
        // is the one used.
        DownloadManager.shared.localURL(for: item)
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

        var rows: [(queueIndex: Int, item: AVPlayerItem)] = []
        var lastArmed = index
        // A window of the run, not all of it — see `streamWindow`.
        for queueIndex in index...min(end, index + Self.streamWindow - 1) {
            let item = queue[queueIndex]
            // A later song still in iCloud ends the run here; the next arm
            // fetches it.
            if queueIndex > index, cloudPendingURL(for: item) != nil { break }
            guard let url = await streamURL(for: item) else { continue }
            rows.append((queueIndex, AVPlayerItem(url: url)))
            lastArmed = queueIndex
        }
        // The user skipped elsewhere meanwhile — that call owns playback now.
        guard playToken == token else { return }
        guard !rows.isEmpty else {
            advancePastRun(endingAt: lastArmed)
            return
        }

        activateAudioSession(for: "the stream run at \(index)")

        streamRun = [:]
        for row in rows { register(row.item, at: row.queueIndex) }
        let player = AVQueuePlayer(items: rows.map(\.item))
        streamPlayer = player
        player.volume = streamVolume
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

    /// Hands a TuneIn station to a stream player of its own, in front of
    /// the queue (`playStation(_:)`). Its URL is resolved from the station's
    /// id first, the one network hop the stream backend makes. `runEnd`
    /// stays at -1, as for an Apple station: no queue row is in this player,
    /// so the top-up and the queue's edits leave it alone.
    private func armStationStream(_ station: PlayableContent, token: Int) async throws {
        isLoading = true
        defer { if playToken == token { isLoading = false } }
        guard let url = await streamURL(for: station) else {
            guard playToken == token else { return }
            throw LocalPlaybackError.stationNotFound
        }
        guard playToken == token else { return }

        activateAudioSession(for: "the station \(station.content.id)")
        let playerItem = AVPlayerItem(url: url)
        listenForStreamTitles(on: playerItem, token: token)
        streamRun = [:]
        stationItem = ObjectIdentifier(playerItem)
        watch(playerItem)
        let player = AVQueuePlayer(items: [playerItem])
        streamPlayer = player
        player.volume = streamVolume
        player.play()

        backend = .stream
        runEnd = -1
        pollStationMetadata(for: station, token: token)
        isPlayingLocalStream = true
        nowPlayingCard.begin()
        nowPlayingCard.update(
            item: nowPlayingDisplay,
            isPlaying: true,
            duration: 0,
            elapsed: 0,
            canSkip: false,
            isLive: true
        )
    }

    /// Takes the audio session for a stream player. The player goes on
    /// regardless and plays nothing when this fails, so the log line is
    /// what says why it's silent.
    private func activateAudioSession(for what: String) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            let code = (error as NSError).code
            Self.log.error("activating the audio session for \(what, privacy: .public) failed: \(code) \(error.localizedDescription, privacy: .public)")
        }
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

    /// Takes the Apple station's current entry as what's on air. The player
    /// hands its entries' artwork over as a `musickit://` URL that only
    /// MusicKit's own views can draw, so the real image is unwrapped from it
    /// — and when there's none to unwrap, looked up the way a TuneIn song's
    /// is. Compared by song rather than as a whole, so the cover and match a
    /// lookup filled in aren't wiped on the next poll.
    private func noteStationEntry(_ entry: ApplicationMusicPlayer.Queue.Entry) {
        // A transient entry has no title yet; the next poll will.
        guard !entry.title.isEmpty else { return }
        let artwork = Self.drawableArtworkURL(entry.artwork?.url(width: 600, height: 600))
        var match: PlayableContent?
        if case .song(let song) = entry.item {
            let base = song.toPlayable
            let songArtwork = artwork ?? Self.drawableArtworkURL(base.artwork)
            match = PlayableContent(
                title: base.title,
                subtitle: base.subtitle,
                thumbnail: Self.drawableArtworkURL(base.thumbnail) ?? songArtwork,
                artwork: songArtwork,
                content: base.content,
                previewURL: base.previewURL,
                metadata: base.metadata
            )
        }
        let artworkURL = artwork ?? match?.artwork

        if let live = liveMetadata, live.song == entry.title, live.artist == entry.subtitle {
            // The same song: fill in what arrived late, if anything did.
            if live.artworkURL == nil, let artworkURL { liveMetadata?.artworkURL = artworkURL }
            if live.match == nil, let match { liveMetadata?.match = match }
            return
        }

        let live = LiveStationMetadata(song: entry.title, artist: entry.subtitle, artworkURL: artworkURL, match: match)
        liveMetadata = live
        if artworkURL == nil || match == nil {
            let token = playToken
            Task { await lookUpArtwork(for: live, token: token) }
        }
    }

    /// An artwork URL the image pipeline can load: an `http(s)` one as is, or
    /// the `https` one a `musickit://` URL wraps. Nil for anything else.
    private static func drawableArtworkURL(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "http" || scheme == "https" { return url }
        guard scheme == "musickit",
              let range = url.absoluteString.range(of: #"https%3A%2F%2F[^&]+"#, options: .regularExpression),
              let unwrapped = String(url.absoluteString[range]).removingPercentEncoding else { return nil }
        return URL(string: unwrapped)
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
    /// song it plays. Read off what's playing rather than `backend` so a
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
            // `@Observable` notifies on every write, equal or not — so each is
            // written only when it changed, and `progress` only when the
            // player has moved off the running clock (`noteProgress`).
            // Writing them every tick re-rendered the whole screen twice a
            // second, artwork and backdrop included.
            let playing = reconcilePlaying(status == .playing)
            let paused = isPlaying && !playing
            if isPlaying != playing { isPlaying = playing }

            // The run's entry the player is on. A skip shown ahead of the
            // player (`appleSkipHold`) holds until the player gets there:
            // until then its clock and entry are still the old song's.
            let entries = musicPlayer.queue.entries
            let currentEntry = musicPlayer.queue.currentEntry
            let entryIndex = currentEntry.flatMap { current in entries.firstIndex { $0.id == current.id } }
            let playerRow = entryIndex.flatMap { appleRun[safe: entries.distance(from: entries.startIndex, to: $0)] }
            if let hold = appleSkipHold, hold.until > .now, playerRow?.queueIndex != hold.queueIndex {
                // Still on its way.
            } else {
                appleSkipHold = nil
            }
            let followsPlayer = appleSkipHold == nil

            if followsPlayer {
                noteProgress(Self.finite(musicPlayer.playbackTime, else: progress))
            }
            if status == .playing { appleWasPlaying = true }
            // Playing well past a stall: the next one there gets armed again too.
            if status == .playing, progress > 10 { appleStallIndex = nil }
            savePositionIfDue(paused: paused)

            // A station's entries are the songs it streams; the current one
            // is what's on air.
            if backend == .appleStation, let entry = musicPlayer.queue.currentEntry {
                noteStationEntry(entry)
            }

            // Follow the player's own advance through the run.
            if followsPlayer, let current = currentEntry, entryIndex != nil {
                if let row = playerRow {
                    if currentIndex != row.queueIndex { currentIndex = row.queueIndex }
                    let songDuration = row.duration ?? catalogDuration(at: row.queueIndex)
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
            if backend == .appleMusic {
                if status == .playing, progress >= 1 {
                    appleRunExpectedEnd = onLastEntry && duration > 0
                        ? Date.now.addingTimeInterval(max(0, duration - progress))
                        : nil
                } else if status == .paused, progress >= 1, progress < duration - 0.75 {
                    // Paused partway through: the clock stops with it.
                    appleRunExpectedEnd = nil
                }
            }
            fillAppleRun()
            prepareNextRun()
            // Past the end of the last entry by the clock, and parked either
            // at its end or back at the top — some OS versions rewind the
            // finished queue (to zero, or to its first entry) and read
            // `.paused`. A pause partway through a track is neither.
            let pastRunEnd = appleRunExpectedEnd.map { Date.now >= $0.addingTimeInterval(-1.5) } ?? false
            let ended = status == .stopped
                || (status == .paused && onLastEntry && duration > 0 && progress >= duration - 0.75)
                || (status == .paused && pastRunEnd && (progress < 1 || progress >= duration - 0.75))
            if appleWasPlaying, ended {
                appleWasPlaying = false
                // A station has no run to advance past; it waits to be
                // played again.
                if station != nil {
                    stationStopped()
                    return
                }
                let end = runEnd
                // Stopped short of its last entry: not the end of the run
                // but the player giving up, which it can do when its queue
                // is changed. Arm the song again rather than skip every song
                // still queued after it — once, so one it keeps stopping on
                // is gone past instead.
                if status == .stopped, !onLastEntry, appleStallIndex != currentIndex {
                    let index = currentIndex
                    let position = progress
                    Self.log.error("the Apple player stopped short at \(index); arming it again")
                    appleStallIndex = index
                    teardownRun()
                    Task { try? await arm(at: index, from: position > 2 ? position : nil) }
                    return
                }
                teardownRun()
                advancePastRun(endingAt: end)
            }
        case .stream:
            guard let streamPlayer else { return }
            guard let current = streamPlayer.currentItem else {
                // A station's stream ended or dropped.
                if station != nil {
                    stationStopped()
                    return
                }
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
                // Reported by its watch (`streamItemFailed`); this only
                // moves on, in case the player hasn't.
                streamItemFailed(current)
                streamPlayer.advanceToNextItem()
                return
            }
            // Only what changed, as above.
            let playing = reconcilePlaying(streamPlayer.timeControlStatus != .paused)
            let paused = isPlaying && !playing
            if isPlaying != playing { isPlaying = playing }
            // However it was paused — in the app, from the car's stop
            // button, a sleep timer — so Play knows how long it's been.
            if station != nil {
                if streamPlayer.timeControlStatus != .paused {
                    stationPausedAt = nil
                } else if stationPausedAt == nil {
                    stationPausedAt = .now
                }
            }
            noteProgress(Self.finite(current.currentTime().seconds, else: progress))
            savePositionIfDue(paused: paused)
            if let queueIndex = streamRun[ObjectIdentifier(current)], currentIndex != queueIndex {
                currentIndex = queueIndex
            }
            topUpStreamRun()
            // `AVPlayerItem.duration` is indefinite until the item is ready
            // to play — and for good if it never gets there. The catalog's
            // length stands in until then so the scrubber doesn't vanish.
            // A station has none: the catalog's would be the queue's song's.
            let total = current.duration.seconds
            let itemDuration = station != nil ? 0 : total.isFinite && total > 0 ? total : catalogDuration(at: currentIndex)
            if duration != itemDuration { duration = itemDuration }
            prepareNextRun()
            if audioQualityItem != ObjectIdentifier(current) {
                audioQualityItem = ObjectIdentifier(current)
                readAudioQuality(of: current)
            }
            nowPlayingCard.update(
                item: nowPlayingDisplay,
                isPlaying: isPlaying,
                duration: duration,
                elapsed: progress,
                canSkip: station == nil && currentIndex + 1 < queue.count,
                isLive: station != nil
            )
            // Plex and Subsonic hear about the play, as from their own apps.
            PlayReporter.shared.observe(
                streamRun[ObjectIdentifier(current)].flatMap { queue[safe: $0] },
                playID: ObjectIdentifier(current),
                position: progress,
                duration: duration,
                isPlaying: isPlaying
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
        isRestoring = true
        defer { isRestoring = false }
        // The station that was playing in front of the queue, if one was.
        let savedStation = LocalQueueStore.loadStation().flatMap { playableStation(in: [$0]) }
        station = savedStation
        guard let saved = LocalQueueStore.load(), !saved.queue.isEmpty else { return }
        // Only what the queue would take today: a row an earlier build let
        // in would otherwise sit at the front of the player for good, and be
        // carried onto every speaker chosen. A station among them, from a
        // build that queued them, goes in front of the queue when it was the
        // one playing.
        let kept = queueable(saved.queue)
        let current = saved.queue[safe: saved.position.index]
        if station == nil, let current, let legacy = playableStation(in: [current]) {
            station = legacy
            LocalQueueStore.save(station: legacy)
        }
        guard !kept.isEmpty else {
            LocalQueueStore.clear()
            return
        }
        origins = saved.origins
        let currentKept = current.flatMap { kept.firstIndex(of: $0) }
        queue = kept
        currentIndex = currentKept ?? 0
        repeatMode = saved.position.repeatMode
        isShuffled = saved.position.isShuffled ?? false
        unshuffledUpNext = isShuffled ? queueable(saved.unshuffled ?? []) : nil
        // The position belongs to the track that was current; with that
        // one dropped, the queue starts from the top of what's left.
        let hasSpot = currentKept != nil && saved.position.progress.isFinite && saved.position.progress > 2
        // Under a couple of seconds is the start of the track as far as
        // anyone can tell, the same cutoff a route switch uses.
        if hasSpot {
            resumePosition = saved.position.progress
        }
        // Behind a station the queue's spot only waits: the player shows
        // the station, which has no length and no position.
        if station == nil {
            duration = currentKept == nil ? 0 : Self.finite(saved.position.duration, else: 0)
            if hasSpot { progress = saved.position.progress }
        }
        savedProgress = progress
        // The observer may or may not run for an assignment in `init`; the
        // cache wants to know either way, and the call is debounced.
        cacheNeedsRefresh()
        // Rows were dropped (a station from a build that queued them, a row
        // that won't play any more): the file still has them, and the index
        // saved from here on would count against it. Written once the
        // restore is over, which suppresses saves.
        if kept.count != saved.queue.count {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.writeQueue()
                LocalQueueStore.save(unshuffled: self.unshuffledUpNext)
                self.savePosition()
            }
        }
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
    ///
    /// Behind a station it's the spot the queue was left at, not the
    /// station's time: that's what Play on the queue picks up from.
    private func savePosition(waitUntilDone: Bool = false) {
        guard !isRestoring, !queue.isEmpty else { return }
        savedProgress = progress
        let parked = station != nil
        LocalQueueStore.save(
            position: .init(
                index: currentIndex,
                progress: parked ? (resumePosition ?? 0) : progress,
                duration: parked ? catalogDuration(at: currentIndex) : duration,
                repeatMode: repeatMode,
                isShuffled: isShuffled
            ),
            waitUntilDone: waitUntilDone
        )
    }

    /// Writes where the queued tracks were played from, so the player still
    /// names the origin after a relaunch. Written only when it changes: once
    /// per Play, and once per page a long container adds behind it.
    private func saveSource() {
        guard !isRestoring else { return }
        LocalQueueStore.save(origins: origins)
    }

    /// The poll's version: every few seconds of progress, and at the moment
    /// playback pauses so the saved spot is the one the scrubber shows.
    /// Nothing behind a station, whose time isn't the queue's.
    private func savePositionIfDue(paused: Bool) {
        guard station == nil else { return }
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
        savePosition(waitUntilDone: true)
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

/// The device queue and its position, kept across launches, in files in
/// Application Support beside the song cache: the queue can run to
/// thousands of rows, and the position changes every few seconds of
/// playback. An empty queue clears both.
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
        /// Optional so a position saved before shuffle was a switch still
        /// reads.
        var isShuffled: Bool? = nil
    }

    struct Saved {
        var queue: [PlayableContent]
        var position: Position
        /// Up Next in its real order, while shuffle is on.
        var unshuffled: [PlayableContent]?
        /// Where each queued track was played from, by track ID.
        var origins: [String: PlayableContent]
    }

    private static var queueURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("LocalQueue.json")
    }

    /// Beside the queue file, which stays a bare `[PlayableContent]`.
    private static var unshuffledURL: URL? {
        queueURL?.deletingLastPathComponent().appendingPathComponent("LocalQueueUnshuffled.json")
    }

    /// The station playing in front of the queue (`station`), beside it.
    /// Its own file, kept or removed only with the station: the queue's
    /// `clear()` leaves it, since a station can play with no queue at all.
    private static var stationURL: URL? {
        queueURL?.deletingLastPathComponent().appendingPathComponent("LocalStation.json")
    }

    /// Beside the queue. The position used to be kept in the defaults, and
    /// every write there re-ran each view that reads a stored setting
    /// (`@AppStorage`): the app's root, Browse, Search and their rows, every
    /// five seconds of playback.
    private static var positionURL: URL? {
        queueURL?.deletingLastPathComponent().appendingPathComponent("LocalQueuePosition.json")
    }

    /// Where the position was kept before `positionURL`: read when there's
    /// no file yet, so an update doesn't lose the spot.
    private static var positionKey: String { AppStorageKeys.localQueuePosition }
    /// One row, so it sits in the defaults beside the position rather than
    /// in the queue file — which stays a bare `[PlayableContent]`, readable
    /// by builds that predate the origin.
    private static var sourceKey: String { AppStorageKeys.localQueueSource }

    static func load() -> Saved? {
        guard let queueURL, let data = try? Data(contentsOf: queueURL),
              let queue = try? JSONDecoder().decode([PlayableContent].self, from: data) else { return nil }
        let position = (positionURL.flatMap { try? Data(contentsOf: $0) } ?? UserDefaults.standard.data(forKey: positionKey))
            .flatMap { try? JSONDecoder().decode(Position.self, from: $0) }
            ?? Position(index: 0, progress: 0, duration: 0, repeatMode: .off)
        let origins = UserDefaults.standard.data(forKey: sourceKey)
            .flatMap { Origins.decode($0, queue: queue) } ?? [:]
        let unshuffled = unshuffledURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([PlayableContent].self, from: $0) }
        return Saved(queue: queue, position: position, unshuffled: unshuffled, origins: origins)
    }

    static func loadStation() -> PlayableContent? {
        stationURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(PlayableContent.self, from: $0) }
    }

    /// Written on the same serial queue as the queue file; nil removes it.
    static func save(station: PlayableContent?) {
        io.async {
            guard let url = Self.stationURL else { return }
            guard let station, let data = try? JSONEncoder().encode(station) else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Written on the same serial queue as the queue file, in order.
    static func save(unshuffled: [PlayableContent]?) {
        io.async {
            guard let url = Self.unshuffledURL else { return }
            guard let unshuffled, let data = try? JSONEncoder().encode(unshuffled) else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            try? data.write(to: url, options: .atomic)
        }
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

    /// Written on the same serial queue as the queue file, in order.
    static func save(position: Position, waitUntilDone: Bool = false) {
        let work: @Sendable () -> Void = {
            guard let url = Self.positionURL, let data = try? JSONEncoder().encode(position) else { return }
            try? data.write(to: url, options: .atomic)
        }
        if waitUntilDone {
            io.sync(execute: work)
        } else {
            io.async(execute: work)
        }
    }

    static func save(origins: [String: PlayableContent]) {
        guard !origins.isEmpty, let data = try? JSONEncoder().encode(Origins(origins)) else {
            return UserDefaults.standard.removeObject(forKey: sourceKey)
        }
        UserDefaults.standard.set(data, forKey: sourceKey)
    }

    /// The origins as saved: each distinct one once, and each track ID
    /// pointing at its index — a 1,000-track playlist is one origin, not a
    /// thousand copies of it.
    private struct Origins: Codable {
        var sources: [PlayableContent]
        var tracks: [String: Int]

        init(_ origins: [String: PlayableContent]) {
            var sources: [PlayableContent] = []
            var indices: [PlayableContent: Int] = [:]
            var tracks: [String: Int] = [:]
            for (id, origin) in origins {
                if let index = indices[origin] {
                    tracks[id] = index
                } else {
                    indices[origin] = sources.count
                    tracks[id] = sources.count
                    sources.append(origin)
                }
            }
            self.sources = sources
            self.tracks = tracks
        }

        /// Earlier builds saved one origin for the whole queue; it reads
        /// back as the origin of every track in it.
        static func decode(_ data: Data, queue: [PlayableContent]) -> [String: PlayableContent]? {
            let decoder = JSONDecoder()
            if let saved = try? decoder.decode(Origins.self, from: data) {
                return saved.tracks.compactMapValues { saved.sources[safe: $0] }
            }
            guard let single = try? decoder.decode(PlayableContent.self, from: data) else { return nil }
            return Dictionary(queue.map { ($0.id, single) }, uniquingKeysWith: { first, _ in first })
        }
    }

    static func clear() {
        if let queueURL {
            try? FileManager.default.removeItem(at: queueURL)
        }
        if let unshuffledURL {
            try? FileManager.default.removeItem(at: unshuffledURL)
        }
        if let positionURL {
            try? FileManager.default.removeItem(at: positionURL)
        }
        UserDefaults.standard.removeObject(forKey: positionKey)
        UserDefaults.standard.removeObject(forKey: sourceKey)
    }
}
