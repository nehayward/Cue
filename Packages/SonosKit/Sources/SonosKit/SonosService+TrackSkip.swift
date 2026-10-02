import Foundation
import Nuke

/// Skip presses, made instant.
///
/// Each press used to be its own SOAP `Next`, sent the moment it was pressed on
/// the same connection pool as the 500 ms poll, and the player only showed the
/// new song once the speaker had opened its stream and a read noticed. Mash
/// next and the commands queued behind each other and behind the poll's reads,
/// the speaker worked through them one stream at a time, and the song kept
/// changing for seconds after the last press.
///
/// Now a press does two things, neither of which waits on the network:
///
/// - It moves a target (`TrackSkipPlan`), and one sender per group chases it.
///   For a queue played in order that means jumping straight to the target
///   position; anything else goes out one skip at a time.
/// - It puts the song it's heading to on screen — from the queue, or the
///   socket's `nextItem` — and holds back reads that still describe the song
///   being left (`skipHoldsTrack`) until the speaker reports the target.
extension SonosService {
    /// How long to keep showing the target after the last press or command
    /// while the speaker hasn't reported it. Past this, whatever the speaker
    /// says wins.
    ///
    /// The hold's times are all `ContinuousClock`, not `Date`: the wall clock
    /// can step backwards (a manual change, a network time correction), and a
    /// send time left in the future would drop every read of that group until
    /// the clock caught up — the player frozen on one song.
    static let skipHoldTimeout: Duration = .seconds(2.5)
    /// After the last command, how often and how many times to re-read the
    /// speaker until it agrees — only while the poll isn't running to do it:
    /// backgrounded, the Lock Screen controls drive skips and nothing polls.
    static let skipConfirmInterval: Duration = .milliseconds(300)
    static let skipConfirmAttempts = 6
    /// Queue items fetched for previews: a few behind the target, the rest
    /// ahead of it, since mashing next is the common case.
    static let skipPreviewLookBehind = 5
    static let skipPreviewWindow = 30
    /// Loads covers ahead of the player. Nuke's prefetcher skips covers already
    /// in memory, runs at low priority with capped concurrency, and can be told
    /// to stop the ones a skip has moved past.
    ///
    /// Bound to whichever pipeline is `ImagePipeline.shared` at the time, not
    /// the one there when this was first touched. The app replaces the shared
    /// pipeline at launch with one whose disk cache Settings can clear; a
    /// prefetcher made before that would keep loading through Nuke's default
    /// pipeline, into a second disk cache nothing clears.
    @MainActor
    static var artworkPrefetcher: ImagePrefetcher {
        if let current = currentArtworkPrefetcher, current.pipeline === ImagePipeline.shared {
            return current.prefetcher
        }
        let prefetcher = ImagePrefetcher(pipeline: .shared, destination: .memoryCache)
        currentArtworkPrefetcher = (ImagePipeline.shared, prefetcher)
        return prefetcher
    }
    @MainActor
    private static var currentArtworkPrefetcher: (pipeline: ImagePipeline, prefetcher: ImagePrefetcher)?

    /// Skips `group` a song forward or back.
    ///
    /// Everything before the first suspension — recording the press, putting
    /// the song it leads to on screen — happens at once. The call then returns
    /// once the speaker has been sent every press so far; presses made while
    /// the sender runs wait on the same one.
    @MainActor
    func skip(_ direction: TrackSkipPlan.Direction, on group: GroupRoom) async {
        let existing = activeSkipBurst(for: group)
        let burst = existing ?? makeSkipBurst(for: group)

        let moved = burst.plan.press(
            direction,
            // Where playback is now, not the last report: the stored position
            // only moves when something writes it.
            playbackPosition: group.coordinatorRoom.estimatedPlaybackPosition(),
            queueTotal: group.coordinatorRoom.queueTotal
        )
        guard moved else {
            await burst.sender?.value
            return
        }

        if existing == nil {
            skipBursts[group.coordinatorID] = burst
        }
        // Reads now describe a song being left. That includes the confirmation
        // of an earlier round of this burst, which the sender restarts.
        liveTrackRefreshTasks.removeValue(forKey: group.coordinatorID)?.cancel()
        burst.holdDeadline = ContinuousClock.now + Self.skipHoldTimeout

        showSkipPreview(for: burst, on: group)
        // The bar goes to the start and holds there, ignoring the old song's
        // reports, until the speaker plays from the new one. After the
        // preview: a new song ends the hold.
        group.coordinatorRoom.beginSkip()
        fetchSkipPreviewsIfNeeded(for: burst, on: group)
        prefetchSkipArtwork(for: burst)

        if burst.sender == nil {
            // `guard let self` rather than `self?.`: a single-expression closure
            // takes the optional chain's `()?` as its result type, making this a
            // `Task<()?, Never>`.
            burst.sender = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.runSkipSender(burst, on: group)
            }
        }
        await burst.sender?.value
    }

    /// The group to coalesce a skip on, or `nil` to send a plain one.
    ///
    /// A skip is worked out from the model's track number and position, so the
    /// model has to be kept current — by the poll, or by a socket listening to
    /// the group. On a stale one (a widget extension holding a cached topology)
    /// it would jump to the wrong song.
    @MainActor
    func liveSkipGroup(ip: String) -> GroupRoom? {
        guard let group = groups.first(where: { $0.coordinatorRoom.ip == ip }),
              isRunning || liveConnections[group.coordinatorID] != nil else { return nil }
        return group
    }

    /// Whether a song just read from `group`'s speaker should be dropped
    /// because a skip is still landing — the read would put the song being
    /// left back on screen over the one being skipped to.
    ///
    /// Releases the hold, and returns `false`, once a read shows the speaker
    /// has arrived or the hold has timed out.
    ///
    /// - Parameter readAt: `ContinuousClock.now` when the read was *sent*. A
    ///   read sent before the last command reached the speaker describes the
    ///   old song however late its answer lands — even after a faster read has
    ///   confirmed the new one, since the poll awaits several other calls
    ///   before it looks at its track.
    @MainActor
    public func skipHoldsTrack(on group: GroupRoom, read track: Track, at readAt: ContinuousClock.Instant) -> Bool {
        if let settledAt = lastSkipSettledAt[group.coordinatorID], readAt < settledAt {
            return true
        }
        guard let burst = skipBursts[group.coordinatorID] else { return false }
        if burst.sender != nil {
            return true
        }

        let arrived = burst.plan.isConfirmed(
            position: track.position,
            isStartTrack: track.unique == burst.startTrack.unique
        )
        if !arrived, ContinuousClock.now < burst.holdDeadline {
            return true
        }

        endSkipBurst(burst, on: group)
        return false
    }

    /// Reads the speaker's position before a skip that starts in the
    /// background.
    ///
    /// There only the socket keeps the model, and it reports on change rather
    /// than continuously: the playback position freezes at the last event, and
    /// a missed event leaves the track number one behind. A skip is worked out
    /// from both — a frozen 0:00 turned previous's restart into going back a
    /// song, and a stale track number aims a jump at the song already playing.
    /// One read fixes both: the round trip `previous` always paid before. In
    /// the foreground the poll keeps them current, so presses there don't wait.
    @MainActor
    func refreshPositionForSkip(_ group: GroupRoom) async {
        guard !isRunning, !isLandingSkip(on: group),
              let track = await getTrack(ip: group.coordinatorRoom.ip), !track.isEmpty,
              // A press that landed during the read already zeroed the
              // position on purpose.
              !isLandingSkip(on: group) else { return }
        group.coordinatorRoom.updatePlaybackPosition(track.playbackPosition)
        if group.coordinatorRoom.track.position != track.position {
            group.coordinatorRoom.track.position = track.position
        }
    }

    /// Whether a skip on `group` is still on its way to the speaker. Socket
    /// position updates are dropped meanwhile: they describe the old song.
    @MainActor
    func isLandingSkip(on group: GroupRoom) -> Bool {
        skipBursts[group.coordinatorID]?.isLanding ?? false
    }

    // MARK: - Sending

    @MainActor
    private func runSkipSender(_ burst: TrackSkipBurst, on group: GroupRoom) async {
        while let command = burst.plan.nextCommand {
            guard await sendSkipCommand(command, on: group) else {
                // Refused — most likely a jump past the end of a queue whose
                // length wasn't known yet, or a source that stopped being the
                // queue. Stop guessing: drop the run and show what the speaker
                // is actually playing.
                burst.sender = nil
                endSkipBurst(burst, on: group)
                try? await updateTrackInformation(for: [group])
                return
            }
            burst.plan.didSend(command)
            let settledAt = ContinuousClock.now
            lastSkipSettledAt[group.coordinatorID] = settledAt
            burst.holdDeadline = settledAt + Self.skipHoldTimeout
        }
        burst.sender = nil

        guard burst.plan.commandsSent > 0 else {
            // The presses cancelled out before anything went out, so the
            // speaker never left the song. Put it back as it was.
            endSkipBurst(burst, on: group)
            if group.coordinatorRoom.track != burst.startTrack {
                group.coordinatorRoom.track = burst.startTrack
            }
            // Releases the press's hold at 0: the bar goes back to where the
            // song was, and the speaker, still playing it, confirms at once.
            group.coordinatorRoom.beginSeek(to: burst.startPlaybackPosition)
            return
        }

        // A jump is meant to carry playback over to the new song, as `Next`
        // always did; asking for play makes sure of it. Not awaited, and not
        // tied to the burst: nothing needs to wait on it, and a press that
        // lands meanwhile mustn't cancel it.
        if case .queue = burst.plan.mode, burst.wasPlaying {
            let api = self.api
            let ip = group.coordinatorRoom.ip
            Task { await api.play(ipAddress: ip) }
        }

        // While the poll runs it re-reads every group, and its reads release
        // the hold. Otherwise confirm here. Kept in the player's refresh slot,
        // so it and the socket's own refresh replace each other rather than
        // both re-reading the speaker.
        guard !isRunning else { return }
        liveTrackRefreshTasks[group.coordinatorID]?.cancel()
        liveTrackRefreshTasks[group.coordinatorID] = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.confirmSkip(burst, on: group)
        }
    }

    /// Sends one command as SOAP on the transport session.
    ///
    /// - Returns: Whether the speaker accepted it.
    @MainActor
    private func sendSkipCommand(_ command: TrackSkipPlan.Command, on group: GroupRoom) async -> Bool {
        let ip = group.coordinatorRoom.ip
        switch command {
        case .jump(let position):
            return await api.seek(trackNumber: position, IP: ip)
        case .restart:
            // `TimeInterval`, not a bare `0`: that resolves to the relative
            // `TIME_DELTA` overload, which seeks nowhere.
            return await api.seek(to: TimeInterval(0), IP: ip)
        case .step(forward: true):
            return await api.next(ipAddress: ip)
        case .step(forward: false):
            return await api.previous(ipAddress: ip)
        }
    }

    /// Re-reads the speaker until it reports the target.
    @MainActor
    private func confirmSkip(_ burst: TrackSkipBurst, on group: GroupRoom) async {
        for _ in 0..<Self.skipConfirmAttempts {
            try? await Task.sleep(for: Self.skipConfirmInterval)
            guard !Task.isCancelled, skipBursts[group.coordinatorID] === burst else { return }
            try? await updateTrackInformation(for: [group])
        }

        // Never agreed. Stop holding: whatever the speaker reports now is the
        // truth.
        guard !Task.isCancelled, skipBursts[group.coordinatorID] === burst else { return }
        endSkipBurst(burst, on: group)
        try? await updateTrackInformation(for: [group])
    }

    // MARK: - Bursts

    @MainActor
    private func activeSkipBurst(for group: GroupRoom) -> TrackSkipBurst? {
        guard let burst = skipBursts[group.coordinatorID] else { return nil }
        if burst.isLanding {
            return burst
        }
        endSkipBurst(burst, on: group)
        return nil
    }

    @MainActor
    private func makeSkipBurst(for group: GroupRoom) -> TrackSkipBurst {
        let track = group.coordinatorRoom.track
        // Absolute jumps need the queue's own order. Shuffled, the next song
        // isn't the next position, and for Spotify Connect or a cloud queue the
        // Sonos queue isn't what's playing at all.
        let mode: TrackSkipPlan.Mode
        if group.playbackService == .queue, !group.playMode.isShuffleEnabled, track.position > 0 {
            mode = .queue(wrapsAround: group.playMode.isRepeatAllEnabled)
        } else {
            mode = .relative
        }

        return TrackSkipBurst(
            plan: TrackSkipPlan(mode: mode, startPosition: track.position),
            startTrack: track,
            startPlaybackPosition: group.coordinatorRoom.estimatedPlaybackPosition(),
            wasPlaying: group.coordinatorRoom.isPlaying,
            nextPreview: liveNextPreview(for: group, position: track.position + 1)
        )
    }

    /// Doesn't cancel a confirmation in progress: this runs from inside it (a
    /// confirming read releases the hold), and cancelling would abort the
    /// metadata and artwork fetch for the very song that just arrived. The
    /// confirmation notices the burst is gone and stops on its own.
    @MainActor
    func endSkipBurst(_ burst: TrackSkipBurst, on group: GroupRoom) {
        burst.previewFetch?.cancel()
        burst.previewFetch = nil
        if skipBursts[group.coordinatorID] === burst {
            skipBursts.removeValue(forKey: group.coordinatorID)
        }
    }

    // MARK: - Previews

    /// Puts the song the presses lead to on screen, if it's known. When it
    /// isn't, the song on screen stays and the hold keeps the old one's reads
    /// off it until the real one arrives.
    @MainActor
    private func showSkipPreview(for burst: TrackSkipBurst, on group: GroupRoom) {
        let target = burst.plan.target
        // Already showing this target — say from the socket, before the queue
        // window landed. A second write of the same song would only re-run
        // every track consumer and reload its cover from another URL.
        guard burst.shownTarget != target, var preview = skipPreview(for: burst, on: group) else { return }
        preview.inheritAlbumArtwork(from: group.coordinatorRoom.track)
        burst.shownTarget = target
        if group.coordinatorRoom.track != preview {
            group.coordinatorRoom.track = preview
            // A new song ends the room's skip hold; this one hasn't landed.
            group.coordinatorRoom.beginSkip()
        }
    }

    @MainActor
    private func skipPreview(for burst: TrackSkipBurst, on group: GroupRoom) -> Track? {
        let plan = burst.plan
        let target = plan.target
        if target == plan.startPosition {
            return burst.startTrack
        }
        // Freshest first: the window fetched for this burst (queue mode only),
        // then the socket's next item.
        if let item = burst.queuePreviews[target] {
            return Track(skipPreviewOf: item, position: target)
        }
        if target == plan.startPosition + 1, var next = burst.nextPreview {
            next.position = target
            return next
        }
        // `Room.queue` is only filled in by the queue screen, and may be from
        // long ago.
        guard case .queue = plan.mode,
              let item = group.coordinatorRoom.queue.first(where: { $0.metadata?.position == target }) else { return nil }
        return Track(skipPreviewOf: item, position: target)
    }

    /// Fetches the stretch of queue around the target, so presses after the
    /// first have a song to show. The first press uses the socket's `nextItem`.
    @MainActor
    private func fetchSkipPreviewsIfNeeded(for burst: TrackSkipBurst, on group: GroupRoom) {
        guard case .queue = burst.plan.mode, burst.previewFetch == nil else { return }

        // Covered when the window holds the target and a song either side, so
        // the next press is covered too.
        let target = burst.plan.target
        let needed = max(1, target - 1)...(target + 1)
        if let range = burst.previewRange, range.contains(needed.lowerBound), range.contains(needed.upperBound) {
            return
        }

        let first = max(1, target - Self.skipPreviewLookBehind)
        burst.previewRange = first...(first + Self.skipPreviewWindow - 1)
        let needsTotal = group.coordinatorRoom.queueTotal == 0

        burst.previewFetch = Task { @MainActor [weak self] in
            guard let self else { return }
            // `getQueue` takes a 0-based index; queue positions are 1-based.
            async let items = self.getQueue(ip: group.ip, with: first - 1, total: Self.skipPreviewWindow)
            var fetchedTotal: Int?
            if needsTotal {
                fetchedTotal = try? await self.getQueueTotal(group: group)
            }
            let fetchedItems = await items
            guard !Task.isCancelled else { return }
            burst.previewFetch = nil

            for item in fetchedItems {
                if let position = item.metadata?.position {
                    burst.queuePreviews[position] = item
                }
            }
            // Lets later presses clamp to the end of the queue, or wrap.
            if let fetchedTotal, fetchedTotal > 0, group.coordinatorRoom.queueTotal != fetchedTotal {
                group.coordinatorRoom.queueTotal = fetchedTotal
            }

            // The presses made while this was in flight were drawn without it.
            guard self.skipBursts[group.coordinatorID] === burst else { return }
            self.showSkipPreview(for: burst, on: group)
            self.fetchSkipPreviewsIfNeeded(for: burst, on: group)
            self.prefetchSkipArtwork(for: burst)
        }
    }

    /// Loads the covers of the songs the next press could land on, and stops
    /// loading the ones a press has moved past.
    ///
    /// The player holds the outgoing cover until the incoming one has loaded,
    /// so a natural track change never flashes the placeholder. Mid-skip that
    /// meant the old song's cover sat under the new song's title for as long
    /// as the speaker took to serve the art — and mashing next cancelled each
    /// load before it finished. Loaded ahead, the cover is in the cache by the
    /// time its song comes up.
    @MainActor
    private func prefetchSkipArtwork(for burst: TrackSkipBurst) {
        guard case .queue = burst.plan.mode else { return }
        let target = burst.plan.target
        let requests = [target + 1, target + 2, target - 1].compactMap { position in
            burst.queuePreviews[position].flatMap { Track(skipPreviewOf: $0, position: position).playerArtworkRequest }
        }

        let wanted = Set(requests.compactMap(\.imageID))
        let passed = burst.artworkPrefetches.filter { !wanted.contains($0.imageID ?? "") }
        Self.artworkPrefetcher.stopPrefetching(with: passed)
        Self.artworkPrefetcher.startPrefetching(with: requests)
        burst.artworkPrefetches = requests
    }

    /// The socket's `nextItem` as a preview, while it still follows the song on
    /// screen. Not under repeat-one, where the speaker's next item is the same
    /// song again but a skip still moves on.
    @MainActor
    private func liveNextPreview(for group: GroupRoom, position: Int) -> Track? {
        guard !group.playMode.isRepeatOneEnabled,
              let entry = liveNextItems[group.coordinatorID],
              entry.currentName == group.coordinatorRoom.track.name else {
            return nil
        }
        return Track(skipPreviewOf: entry.next, musicService: group.coordinatorRoom.track.musicService, position: position)
    }
}

/// A run of skip presses on one group, from the first press until the speaker
/// has caught up. `TrackSkipPlan` holds the arithmetic; this holds the timing
/// and the previews. Only touched on the main actor.
final class TrackSkipBurst {
    var plan: TrackSkipPlan
    /// The song on screen when the first press landed: put back if the presses
    /// cancel out, and how relative mode tells that the speaker has moved.
    let startTrack: Track
    let startPlaybackPosition: TimeInterval
    /// Whether the group was playing when the first press landed.
    let wasPlaying: Bool
    /// The socket's `nextItem` when the first press landed.
    let nextPreview: Track?
    /// Queue items fetched for previews, by queue position.
    var queuePreviews: [Int: PlayableContent] = [:]
    /// The positions the last preview fetch asked for. Not derivable from
    /// `queuePreviews`: positions past the end never appear there.
    var previewRange: ClosedRange<Int>?
    var previewFetch: Task<Void, Never>?
    /// The target whose preview is on screen.
    var shownTarget: Int?
    /// Covers being loaded ahead of the target.
    var artworkPrefetches: [ImageRequest] = []
    /// Works the plan off. `nil` once the speaker has been sent everything.
    var sender: Task<Void, Never>?
    /// When to stop waiting for the speaker to report the target. Set by every
    /// press and every accepted command.
    var holdDeadline = ContinuousClock.now

    /// Commands still going out, or the speaker not yet given up on.
    var isLanding: Bool { sender != nil || ContinuousClock.now < holdDeadline }

    init(plan: TrackSkipPlan, startTrack: Track, startPlaybackPosition: TimeInterval, wasPlaying: Bool, nextPreview: Track?) {
        self.plan = plan
        self.startTrack = startTrack
        self.startPlaybackPosition = startPlaybackPosition
        self.wasPlaying = wasPlaying
        self.nextPreview = nextPreview
    }
}

/// The song after the one playing, as the socket last reported it, and which
/// song that was relative to.
struct LiveNextItem {
    let currentName: String
    let next: SonosTrackInfo
}

extension Track {
    init(skipPreviewOf item: PlayableContent, position: Int) {
        self.init(
            trackID: item.content.id,
            name: item.title,
            artist: item.metadata?.artist ?? "",
            album: item.metadata?.album ?? "",
            musicService: item.content.service,
            // `Track.duration` is in milliseconds.
            duration: item.metadata?.duration.map { $0 / Duration.milliseconds(1) } ?? 0,
            position: position,
            sonosAlbumArtURL: item.artwork
        )
        isSkipPreview = true
    }

    init?(skipPreviewOf info: SonosTrackInfo, musicService: MusicService, position: Int) {
        guard let name = info.name, !name.isEmpty else { return nil }
        let artworkURL = (info.imageUrl ?? info.images?.first?.url).flatMap { URL(string: $0) }
        self.init(
            trackID: info.id?.objectId ?? "",
            name: name,
            artist: info.artist?.name ?? "",
            album: info.album?.name ?? "",
            musicService: musicService,
            duration: TimeInterval(info.durationMillis ?? 0),
            position: position,
            sonosAlbumArtURL: artworkURL
        )
        isSkipPreview = true
    }
}
