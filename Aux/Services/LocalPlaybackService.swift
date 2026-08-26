import AVFoundation
import Foundation
import MusicKit
import Observation
import SonosKit

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
/// - Plex tracks stream their full file (`previewURL` is the whole track
///   served from the user's server).
///
/// The displayed metadata never needs a fetch — `nowPlaying` is the same
/// `PlayableContent` the search returned. The only network hop is resolving
/// Apple ids into `Song` values, because MusicKit refuses to queue anything
/// less than a real catalog `Song`.
@MainActor
@Observable
final class LocalPlaybackService {
    static let shared = LocalPlaybackService()

    enum LocalPlaybackError: LocalizedError {
        case songNotFound
        case nothingPlayable

        var errorDescription: String? {
            switch self {
            case .songNotFound:
                "Couldn't find this song on Apple Music"
            case .nothingPlayable:
                "Nothing here can play on this device"
            }
        }
    }

    private enum Backend {
        case appleMusic
        case stream
    }

    // MARK: - Observable queue + now-playing state

    /// The local queue, in play order. Mixed services are fine — playback is
    /// armed per same-service run.
    private(set) var queue: [PlayableContent] = []
    private(set) var currentIndex: Int = 0
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var progress: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    var nowPlaying: PlayableContent? { queue[safe: currentIndex] }
    var upNext: [PlayableContent] { Array(queue.dropFirst(currentIndex + 1)) }
    var isActive: Bool { !queue.isEmpty }

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

    /// Whether the queue can take this item: Apple tracks (catalog or library)
    /// and Plex tracks that carry their stream URL.
    func canPlayLocally(_ item: PlayableContent) -> Bool {
        backendKind(for: item) != nil
    }

    private func backendKind(for item: PlayableContent) -> Backend? {
        switch item.content.service {
        case .apple where [.track, .libraryTrack].contains(item.content.type):
            .appleMusic
        case .plex where item.content.type == .track
            && (item.previewURL != nil || PlexDownloadService.shared.isDownloaded(item)):
            .stream
        default:
            nil
        }
    }

    /// Whether this is an album whose tracks the local queue can take (they
    /// get fetched first — see `albumTracks(for:)`).
    func canPlayAlbumLocally(_ item: PlayableContent) -> Bool {
        switch (item.content.type, item.content.service) {
        case (.album, .apple), (.libraryAlbum, .apple), (.album, .plex):
            true
        default:
            false
        }
    }

    /// The album's tracks, fetched the same way the album detail screen does.
    func albumTracks(for album: PlayableContent) async -> [PlayableContent] {
        switch (album.content.type, album.content.service) {
        case (.album, .apple):
            guard let full: Album = try? await MusicSearchService.shared.lookup(id: album.content.id),
                  let tracks = full.tracks else { return [] }
            return await MusicSearchService.shared.tracksToPlayableWithPreviews(tracks)
        case (.libraryAlbum, .apple):
            return await AppleMusicBrowseService.shared.albumLookup(id: album.content.id)
        case (.album, .plex):
            return await MusicSearchService.shared.lookupPlexAlbumSongs(id: album.content.id)
        default:
            return []
        }
    }

    // MARK: - Queue management

    func play(_ item: PlayableContent) async throws {
        try await play([item])
    }

    /// Replaces the queue with `items` and starts at `index` (an index into
    /// `items` — unplayable rows are dropped, and the start follows the item).
    func play(_ items: [PlayableContent], startingAt index: Int = 0) async throws {
        let playable = items.filter { canPlayLocally($0) }
        guard !playable.isEmpty else { throw LocalPlaybackError.nothingPlayable }
        queue = playable
        let start = items[safe: index].flatMap { playable.firstIndex(of: $0) } ?? 0
        startPolling()
        try await arm(at: start)
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

    /// Jumps to `index` in the queue (e.g. a tap in the Up Next list).
    func play(at index: Int) {
        guard queue.indices.contains(index) else { return }
        Task { try? await arm(at: index) }
    }

    // MARK: - Transport

    func togglePlayback() {
        switch backend {
        case .appleMusic:
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

    func next() {
        let target = currentIndex + 1
        guard target < queue.count else {
            stop()
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
        teardownRun()
        queue = []
        currentIndex = 0
        isPlaying = false
        isLoading = false
        progress = 0
        duration = 0
    }

    // MARK: - Arming runs

    /// The last index of the contiguous same-backend run starting at `index`.
    private func runEnd(from index: Int) -> Int {
        guard let kind = backendKind(for: queue[index]) else { return index }
        var end = index
        while end + 1 < queue.count, backendKind(for: queue[end + 1]) == kind {
            end += 1
        }
        return end
    }

    /// Hands the run starting at `index` to its native player and starts it.
    private func arm(at index: Int) async throws {
        playToken += 1
        let token = playToken
        teardownRun()
        guard queue.indices.contains(index) else {
            stop()
            return
        }
        currentIndex = index
        progress = 0
        duration = 0
        let end = runEnd(from: index)

        switch backendKind(for: queue[index]) {
        case .stream:
            armStream(index: index, end: end)
        case .appleMusic:
            try await armApple(index: index, end: end, token: token)
        case nil:
            // Shouldn't happen — the queue only takes playable items.
            advancePastRun(endingAt: index)
        }
    }

    /// Moves on to whatever follows the armed run, or stops at the queue's end.
    private func advancePastRun(endingAt end: Int) {
        guard end + 1 < queue.count else {
            stop()
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
        case nil:
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

        if previous == .appleMusic {
            musicPlayer.stop()
        }
        if streamPlayer != nil {
            streamPlayer?.pause()
            streamPlayer?.removeAllItems()
            streamPlayer = nil
            streamRun = [:]
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

    private func armApple(index: Int, end: Int, token: Int) async throws {
        isLoading = true
        defer { if playToken == token { isLoading = false } }

        // Resolve the whole run in one catalog request (cache-first), keeping
        // track of which queue rows made it — a failed row is skipped, not
        // fatal to the run.
        var resolved: [(queueIndex: Int, song: Song)] = []
        var missing: [(queueIndex: Int, catalogID: String)] = []
        for queueIndex in index...end {
            guard let catalogID = await catalogID(for: queue[queueIndex]) else { continue }
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
                resolved.append((queueIndex, song))
            }
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
        try await musicPlayer.play()
        guard playToken == token else { return }

        appleRun = resolved
        backend = .appleMusic
        runEnd = end
        currentIndex = first.queueIndex
        duration = first.song.duration ?? 0
    }

    /// The Apple Music catalog id for `item`. Library tracks carry a library id
    /// (`i.…`) the catalog can't fetch, so those are mapped to their catalog
    /// song first — the same way radio seeding does.
    private func catalogID(for item: PlayableContent) async -> String? {
        guard item.content.type == .libraryTrack else { return item.content.id }
        guard let lookup = await MusicSearchService.shared.appleLibraryLookup(id: item.content.id) else { return nil }
        return lookup.data.first?.id
    }

    // MARK: - Stream (Plex) backend

    private func armStream(index: Int, end: Int) {
        let rows: [(queueIndex: Int, item: AVPlayerItem)] = (index...end).compactMap { queueIndex in
            let item = queue[queueIndex]
            // A downloaded copy beats the server URL — it plays with no
            // network, including away from the Plex server entirely.
            guard let url = PlexDownloadService.shared.localURL(for: item) ?? item.previewURL else { return nil }
            return (queueIndex, AVPlayerItem(url: url))
        }
        guard !rows.isEmpty else {
            advancePastRun(endingAt: end)
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
        player.play()

        backend = .stream
        runEnd = end
        currentIndex = rows[0].queueIndex
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
        case .appleMusic:
            let status = musicPlayer.state.playbackStatus
            isPlaying = status == .playing
            progress = musicPlayer.playbackTime
            if status == .playing { appleWasPlaying = true }

            // Follow the player's own advance through the run.
            let entries = musicPlayer.queue.entries
            if let current = musicPlayer.queue.currentEntry,
               let entryIndex = entries.firstIndex(where: { $0.id == current.id }) {
                let offset = entries.distance(from: entries.startIndex, to: entryIndex)
                if let row = appleRun[safe: offset] {
                    currentIndex = row.queueIndex
                    duration = row.song.duration ?? 0
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
            isPlaying = streamPlayer.timeControlStatus != .paused
            progress = current.currentTime().seconds
            let total = current.duration.seconds
            duration = total.isFinite ? total : 0
            if let queueIndex = streamRun[ObjectIdentifier(current)] {
                currentIndex = queueIndex
            }
        case nil:
            isPlaying = false
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// On-disk copy of resolved `Song`s (they're Codable), so tracks Aux has seen
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
