import Foundation

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
///   position; anything else goes out one skip at a time, over the group's open
///   socket when it has one.
/// - It puts the song it's heading to on screen — from the queue, or the
///   socket's `nextItem` — and holds back reads that still describe the song
///   being left (`skipHoldsTrack`) until the speaker reports the target.
extension SonosService {
    /// How long to keep showing the target after the last press or command
    /// while the speaker hasn't reported it. Past this, whatever the speaker
    /// says wins.
    static let skipHoldTimeout: TimeInterval = 2.5
    /// A socket send only means the frame left the phone. Reads issued within
    /// this long of one may still predate the speaker acting on it.
    static let skipSocketGrace: TimeInterval = 0.4
    /// After the last command, how often and how many times to re-read the
    /// speaker until it agrees. The poll would get there too, but it isn't
    /// always running: backgrounded, the Lock Screen controls drive skips and
    /// nothing polls at all.
    static let skipConfirmInterval: Duration = .milliseconds(300)
    static let skipConfirmAttempts = 6
    /// Queue items fetched for previews: a few behind the target, the rest
    /// ahead of it, since mashing next is the common case.
    static let skipPreviewLookBehind = 5
    static let skipPreviewWindow = 30

    /// Skips `group` a song forward or back.
    ///
    /// Returns as soon as the press is recorded and the song it leads to is on
    /// screen. The returned task finishes once the speaker has been sent every
    /// press so far; presses made while it runs share it.
    @MainActor
    @discardableResult
    public func skip(_ direction: TrackSkipPlan.Direction, on group: GroupRoom) -> Task<Void, Never> {
        let existing = activeSkipBurst(for: group)
        let burst = existing ?? makeSkipBurst(for: group)

        let moved = burst.plan.press(
            direction,
            playbackPosition: group.coordinatorRoom.playbackPosition,
            queueTotal: group.coordinatorRoom.queueTotal
        )
        guard moved else {
            return burst.sender ?? Task {}
        }

        if existing == nil {
            skipBursts[group.coordinatorID] = burst
        }
        // A press while the last run is still being confirmed extends that run;
        // its sender will confirm again once this press has gone out too.
        burst.confirmation?.cancel()
        burst.confirmation = nil
        burst.holdDeadline = Date.now.addingTimeInterval(Self.skipHoldTimeout)

        group.coordinatorRoom.updatePlaybackPosition(0)
        showSkipPreview(for: burst, on: group)
        fetchSkipPreviewsIfNeeded(for: burst, on: group)

        if let sender = burst.sender {
            return sender
        }
        // `guard let self` rather than `self?.`: a single-expression closure
        // takes the optional chain's `()?` as its result type, making this a
        // `Task<()?, Never>`.
        let sender = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runSkipSender(burst, on: group)
        }
        burst.sender = sender
        return sender
    }

    /// Whether a song just read from `group`'s speaker should be dropped
    /// because a skip is still landing — the read would put the song being
    /// left back on screen over the one being skipped to.
    ///
    /// Releases the hold, and returns `false`, once a read shows the speaker
    /// has arrived or the hold has timed out.
    ///
    /// - Parameter readAt: When the read was *sent*. A read sent before the last
    ///   command reached the speaker describes the old song however late its
    ///   answer lands, and the poll sends its reads before anything else it
    ///   awaits, so most stale reads look fresh by arrival time.
    @MainActor
    public func skipHoldsTrack(on group: GroupRoom, read track: Track, at readAt: Date) -> Bool {
        guard let burst = skipBursts[group.coordinatorID] else {
            // A slow read can outlive the skip it predates: the poll awaits
            // several other calls before it looks at its track, and by then a
            // faster read may already have confirmed the new song.
            if let settledAt = lastSkipSettledAt[group.coordinatorID], readAt < settledAt {
                return true
            }
            return false
        }
        if burst.sender != nil || readAt < burst.settledAt {
            return true
        }

        let arrived = burst.plan.isConfirmed(
            position: track.position,
            isStartTrack: track.unique == burst.startTrack.unique
        )
        if !arrived, Date.now < burst.holdDeadline {
            return true
        }

        endSkipBurst(burst, on: group)
        return false
    }

    /// Whether `group`'s model is being kept current — by the poll, or by a
    /// socket listening to it. A skip is worked out from the model's track
    /// number and position, so on a stale one (a widget extension holding a
    /// cached topology) it would jump to the wrong song; those keep sending
    /// plain skips.
    @MainActor
    func isKeepingCurrent(_ group: GroupRoom) -> Bool {
        isRunning || liveConnections[group.coordinatorID] != nil
    }

    /// Whether a skip on `group` is still on its way to the speaker. Socket
    /// position updates are dropped meanwhile: they describe the old song.
    @MainActor
    public func isLandingSkip(on group: GroupRoom) -> Bool {
        guard let burst = skipBursts[group.coordinatorID] else { return false }
        return burst.sender != nil || Date.now < burst.holdDeadline
    }

    // MARK: - Sending

    @MainActor
    private func runSkipSender(_ burst: TrackSkipBurst, on group: GroupRoom) async {
        repeat {
            await sendPendingSkips(burst, on: group)
            guard skipBursts[group.coordinatorID] === burst else { return }

            // A jump is meant to carry playback over to the new song, as `Next`
            // always did. Asking for play once at the end makes sure of it
            // without waiting to see, and costs nothing when it did.
            if burst.jumped, burst.wasPlaying {
                burst.jumped = false
                await api.play(ipAddress: group.coordinatorRoom.ip)
            }
            // Presses that landed during the play request still need sending.
        } while burst.plan.nextCommand != nil
        burst.sender = nil

        guard burst.plan.commandsSent > 0 else {
            // The presses cancelled out before anything went out, so the
            // speaker never left the song. Put it back as it was.
            endSkipBurst(burst, on: group)
            if group.coordinatorRoom.track != burst.startTrack {
                group.coordinatorRoom.track = burst.startTrack
            }
            group.coordinatorRoom.updatePlaybackPosition(burst.startPlaybackPosition)
            return
        }

        burst.confirmation = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.confirmSkip(burst, on: group)
        }
    }

    /// Sends commands until the plan has none left. A refusal ends the burst.
    @MainActor
    private func sendPendingSkips(_ burst: TrackSkipBurst, on group: GroupRoom) async {
        while let command = burst.plan.nextCommand {
            let (accepted, viaSocket) = await sendSkipCommand(command, on: group)
            guard accepted else {
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
            if case .jump = command { burst.jumped = true }
            burst.settledAt = Date.now.addingTimeInterval(viaSocket ? Self.skipSocketGrace : 0)
            burst.holdDeadline = burst.settledAt.addingTimeInterval(Self.skipHoldTimeout)
        }
    }

    /// - Returns: Whether the speaker took the command, and whether it went
    ///   over the socket — where "took" only means the frame was sent.
    @MainActor
    private func sendSkipCommand(_ command: TrackSkipPlan.Command, on group: GroupRoom) async -> (accepted: Bool, viaSocket: Bool) {
        let ip = group.coordinatorRoom.ip
        switch command {
        case .jump(let position):
            let accepted = await api.seek(trackNumber: position, IP: ip)
            return (accepted, false)
        case .restart:
            // `TimeInterval`, not a bare `0`: that resolves to the relative
            // `TIME_DELTA` overload, which seeks nowhere.
            let accepted = await api.seek(to: TimeInterval(0), IP: ip)
            return (accepted, false)
        case .step(let forward):
            // The socket is only open while something is listening to this
            // group (the player on screen, the Lock Screen card), and only
            // usable while it's still addressed to this group.
            if let streamingService {
                do {
                    try await streamingService.skip(forward: forward, playerId: group.coordinatorID, groupId: group.id)
                    return (true, true)
                } catch {
                    // Fall through to SOAP.
                }
            }
            let accepted: Bool
            if forward {
                accepted = await api.next(ipAddress: ip)
            } else {
                accepted = await api.previous(ipAddress: ip)
            }
            return (accepted, false)
        }
    }

    /// Re-reads the speaker until it reports the target, so the hold doesn't
    /// depend on the poll running.
    @MainActor
    private func confirmSkip(_ burst: TrackSkipBurst, on group: GroupRoom) async {
        for _ in 0..<Self.skipConfirmAttempts {
            try? await Task.sleep(for: Self.skipConfirmInterval)
            guard !Task.isCancelled, skipBursts[group.coordinatorID] === burst else { return }
            try? await updateTrackInformation(for: [group])
        }

        // Never agreed. Stop holding: whatever the speaker reports now is the
        // truth.
        guard !Task.isCancelled, skipBursts[group.coordinatorID] === burst, burst.sender == nil else { return }
        endSkipBurst(burst, on: group)
        try? await updateTrackInformation(for: [group])
    }

    // MARK: - Bursts

    @MainActor
    private func activeSkipBurst(for group: GroupRoom) -> TrackSkipBurst? {
        guard let burst = skipBursts[group.coordinatorID] else { return nil }
        if burst.sender != nil || Date.now < burst.holdDeadline {
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
            startPlaybackPosition: group.coordinatorRoom.playbackPosition,
            wasPlaying: group.coordinatorRoom.isPlaying,
            nextPreview: liveNextPreview(for: group, position: track.position + 1),
            holdDeadline: Date.now.addingTimeInterval(Self.skipHoldTimeout)
        )
    }

    /// Doesn't cancel the burst's confirmation: this runs from inside it
    /// (a confirming read releases the hold), and cancelling would abort the
    /// metadata and artwork fetch for the very song that just arrived. The
    /// confirmation notices the burst is gone and stops on its own.
    @MainActor
    func endSkipBurst(_ burst: TrackSkipBurst, on group: GroupRoom) {
        burst.previewFetch?.cancel()
        burst.previewFetch = nil
        if skipBursts[group.coordinatorID] === burst {
            skipBursts.removeValue(forKey: group.coordinatorID)
        }
        if burst.plan.commandsSent > 0 {
            lastSkipSettledAt[group.coordinatorID] = burst.settledAt
        }
    }

    // MARK: - Previews

    /// Puts the song the presses lead to on screen, if it's known. When it
    /// isn't, the song on screen stays and the hold keeps the old one's reads
    /// off it until the real one arrives.
    @MainActor
    private func showSkipPreview(for burst: TrackSkipBurst, on group: GroupRoom) {
        guard var preview = skipPreview(for: burst, on: group) else { return }
        let current = group.coordinatorRoom.track

        // Same-album carry, as the poll does: the cover on screen is already
        // the right picture, at full size, so don't drop to the speaker's proxy
        // art while the real song's lookup runs.
        if preview.downloadedArtworkURL == nil,
           preview.albumKeysArtwork,
           preview.album == current.album,
           let artworkURL = current.downloadedArtworkURL {
            preview.downloadedArtworkURL = artworkURL
        }

        if current != preview {
            group.coordinatorRoom.track = preview
        }
    }

    @MainActor
    private func skipPreview(for burst: TrackSkipBurst, on group: GroupRoom) -> Track? {
        let plan = burst.plan
        switch plan.mode {
        case .queue:
            let target = plan.target
            if target == plan.startPosition {
                return burst.startTrack
            }
            // Freshest first. `Room.queue` is only filled in by the queue screen
            // and may be from long ago.
            if let item = burst.queuePreviews[target] {
                return Track(skipPreviewOf: item, position: target)
            }
            if target == plan.startPosition + 1, var next = burst.nextPreview {
                next.position = target
                return next
            }
            if let item = group.coordinatorRoom.queue.first(where: { $0.metadata?.position == target }) {
                return Track(skipPreviewOf: item, position: target)
            }
            return nil
        case .relative:
            switch plan.netSteps {
            case 0: return burst.startTrack
            case 1: return burst.nextPreview
            default: return nil
            }
        }
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
            let items = await self.getQueue(ip: group.ip, with: first - 1, total: Self.skipPreviewWindow)
            var total: Int?
            if needsTotal {
                total = await self.api.getQueueCount(IP: group.ip)
            }
            guard !Task.isCancelled else { return }
            burst.previewFetch = nil

            for item in items {
                if let position = item.metadata?.position {
                    burst.queuePreviews[position] = item
                }
            }
            // Lets later presses clamp to the end of the queue, or wrap.
            if let total, total > 0, group.coordinatorRoom.queueTotal != total {
                group.coordinatorRoom.queueTotal = total
            }

            // The presses made while this was in flight were drawn without it.
            guard self.skipBursts[group.coordinatorID] === burst else { return }
            self.showSkipPreview(for: burst, on: group)
            self.fetchSkipPreviewsIfNeeded(for: burst, on: group)
        }
    }

    /// The socket's `nextItem` as a preview, while it still follows the song on
    /// screen. Not under repeat-one, where the speaker's next item is the same
    /// song again but a skip still moves on.
    @MainActor
    private func liveNextPreview(for group: GroupRoom, position: Int) -> Track? {
        guard !group.playMode.isRepeatOneEnabled,
              let entry = liveNextItems[group.coordinatorID],
              let next = entry.next,
              !entry.currentName.isEmpty,
              entry.currentName == group.coordinatorRoom.track.name else {
            return nil
        }
        return Track(skipPreviewOf: next, musicService: group.coordinatorRoom.track.musicService, position: position)
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
    /// A track jump has gone out since playback was last re-asserted.
    var jumped = false
    /// The socket's `nextItem` when the first press landed.
    let nextPreview: Track?
    /// Queue items fetched for previews, by queue position.
    var queuePreviews: [Int: PlayableContent] = [:]
    /// The positions the last preview fetch asked for.
    var previewRange: ClosedRange<Int>?
    var previewFetch: Task<Void, Never>?
    /// Works the plan off. `nil` once the speaker has been sent everything.
    var sender: Task<Void, Never>?
    /// Re-reads the speaker after the sender finishes, until it agrees.
    var confirmation: Task<Void, Never>?
    /// A read sent before this may predate the last command reaching the
    /// speaker.
    var settledAt: Date = .distantPast
    /// When to stop waiting for the speaker to report the target.
    var holdDeadline: Date

    init(plan: TrackSkipPlan, startTrack: Track, startPlaybackPosition: TimeInterval, wasPlaying: Bool, nextPreview: Track?, holdDeadline: Date) {
        self.plan = plan
        self.startTrack = startTrack
        self.startPlaybackPosition = startPlaybackPosition
        self.wasPlaying = wasPlaying
        self.nextPreview = nextPreview
        self.holdDeadline = holdDeadline
    }
}

/// The song after the one playing, as the socket last reported it, and which
/// song that was relative to.
struct LiveNextItem {
    let currentName: String
    let next: SonosTrackInfo?
}

extension Track {
    /// Marks a preview's id so it never shares `unique` with the real song that
    /// replaces it. Sharing it sent the poll down its same-song path, which only
    /// reconciles position — the real metadata and full-size artwork were never
    /// fetched.
    static let skipPreviewIDPrefix = "skip-preview:"

    init(skipPreviewOf item: PlayableContent, position: Int) {
        // `Track.duration` is in milliseconds.
        var milliseconds: TimeInterval = 0
        if let length = item.metadata?.duration {
            milliseconds = TimeInterval(length.components.seconds) * 1000
                + TimeInterval(length.components.attoseconds) / 1e15
        }
        self.init(
            trackID: Self.skipPreviewIDPrefix + item.trackID,
            name: item.title,
            artist: item.metadata?.artist ?? "",
            album: item.metadata?.album ?? "",
            musicService: item.content.service,
            duration: milliseconds,
            position: position,
            sonosAlbumArtURL: item.artwork
        )
    }

    init?(skipPreviewOf info: SonosTrackInfo, musicService: MusicService, position: Int) {
        guard let name = info.name, !name.isEmpty else { return nil }
        let artworkURL = (info.imageUrl ?? info.images?.first?.url).flatMap { URL(string: $0) }
        self.init(
            trackID: Self.skipPreviewIDPrefix + (info.id?.objectId ?? name),
            name: name,
            artist: info.artist?.name ?? "",
            album: info.album?.name ?? "",
            musicService: musicService,
            duration: TimeInterval(info.durationMillis ?? 0),
            position: position,
            sonosAlbumArtURL: artworkURL
        )
    }
}
