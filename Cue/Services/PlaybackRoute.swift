import Defaults
import Foundation
import Nuke
import Observation
import OSLog
import SonosKit
import SwiftUI

/// Where playback is right now — this device or one Sonos group — and the
/// hand-off between the two.
///
/// `PlayDestination` on its own is only a stored preference: the route button
/// wrote it and the next Play read it, and nothing else moved. Picking a
/// speaker while a song was playing on the phone left the phone playing, the
/// accessory showing the phone, and the volume slider on the phone; the
/// choice had no effect until the next Play. This is the AirPlay half:
/// switching carries the queue across, starts the target where the source
/// left off, stops the source, and the player surfaces follow the route.
///
/// Moving to a speaker parks the phone's queue rather than clearing it: the
/// speaker plays on, and the phone's queue keeps its place for the route
/// coming back, or for the next Play on the device. A speaker's queue lives
/// on the speaker anyway, so nothing is cleared on that side either.
///
/// Views read `destination` and `group` off `shared` rather than the
/// environment: the tab bar accessory and the Next Up panel are hosted
/// outside what `withEnvironments()` installs.
///
/// The player surfaces draw `presented`, a `PlaybackController`, rather than
/// branching on `group` themselves. It is the route, except while a switch
/// is carrying a queue across: then it stays on the source — which is what
/// is still being heard — until the target is playing the same song, so the
/// player never shows the speaker's last track, or an empty one, in between.
@MainActor
@Observable
final class PlaybackRoute {
    static let shared = PlaybackRoute()

    /// `log stream --predicate 'subsystem == "dance.cue" AND category == "route"' --level debug`
    private static let log = Logger(subsystem: "dance.cue", category: "route")

    /// The stored destination, mirrored so views can observe it.
    private(set) var destination: PlayDestination

    /// True from a switch until the target has started playing. The tail of a
    /// long queue keeps filling in after this clears; the accessory shows it,
    /// and nothing is disabled by it — a second choice cancels the first.
    private(set) var isSwitching = false

    /// The hand-off in flight. A new choice cancels it: the URLSession calls
    /// under `SonosService` throw on cancellation, so a queue still filling in
    /// stops where it is rather than racing the next switch.
    @ObservationIgnored private var handoffTask: Task<Void, Never>?
    /// Bumped per switch, so a superseded hand-off's clean-up can't clear
    /// `isSwitching` for the one that replaced it.
    @ObservationIgnored private var switchToken = 0

    @ObservationIgnored private var observers: [Task<Void, Never>] = []

    /// The source the player keeps showing while a hand-off carries its
    /// queue to `destination` — see `presented`. Nil when the player shows
    /// the route as it stands.
    private(set) var hold: Hold?

    struct Hold: Equatable {
        /// What the player shows meanwhile.
        let source: PlayDestination
        /// Whether the source was playing when the switch was made. The
        /// source is paused on the way out, and the transport keeps reading
        /// as it did rather than flicking to Play and back.
        let wasPlaying: Bool
        /// The bars' clock while the hold lasts, which the hand-off keeps
        /// in step with what's heard (see `setHoldClock(_:running:)`):
        /// seconds into the song as of `since`, running from there while
        /// either end is playing. The source is paused on its way out, so
        /// its own clock would stop the bars short of the target's.
        var position: TimeInterval
        var since: Date
        var isClockRunning: Bool
        /// The hand-off has stopped the source: from here nothing is heard
        /// from it, and the volume buttons go to the target.
        var sourceStopped = false

        /// Where the song is at `date`, as far as the hand-off goes.
        func position(at date: Date) -> TimeInterval {
            guard isClockRunning else { return position }
            return position + max(date.timeIntervalSince(since), 0)
        }
    }

    /// Waits for the target to show the carried song, then lets the hold go.
    @ObservationIgnored private var holdRelease: Task<Void, Never>?
    /// Lets a hold go however the hand-off is doing, so a speaker that
    /// never answers can't leave the player on the source.
    @ObservationIgnored private var holdWatchdog: Task<Void, Never>?
    /// `holdLimit` from when the hold began: no re-arming goes past it.
    @ObservationIgnored private var holdDeadline: ContinuousClock.Instant?
    /// The longest a hold lasts once the source has stopped: past it the
    /// player follows the route, however the target is doing.
    private static let holdTimeout: Duration = .seconds(12)
    /// The longest it lasts at all. The source is still playing until the
    /// hand-off stops it, and the hold is right to show it meanwhile, but its
    /// transport rests; a hand-off stuck on the network shouldn't keep it.
    private static let holdLimit: Duration = .seconds(30)
    /// How long the player waits, once the target is playing, for it to name
    /// the carried song and have its cover.
    private static let holdSettleLimit: Duration = .seconds(3)

    /// Each speaker's transport source, read when the Play On sheet opened,
    /// keyed by coordinator. Lets a hand-off picked from that sheet skip the
    /// read it would otherwise make before the first note.
    @ObservationIgnored private var prefetched: [String: (service: PlaybackService, at: Date)] = [:]
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    /// Long enough to cover reading the sheet and tapping; short enough that
    /// a speaker someone has since put on the radio isn't taken as still on
    /// its queue.
    private static let prefetchLifetime: TimeInterval = 10

    /// How long each speaker took from Play to PLAYING on its last
    /// hand-offs, keyed by coordinator. The overlapped hand-off seeks this
    /// far ahead of the source so the two line up when the source stops.
    @ObservationIgnored private var startupEstimates: [String: TimeInterval] = [:]
    /// A first guess for a speaker not yet measured this launch.
    private static let defaultStartup: TimeInterval = 0.8
    /// Within this much of the end, the source would move on to the next
    /// song before the speaker picks this one up, so the source stops first.
    private static let overlapTailGuard: TimeInterval = 8

    private init() {
        destination = Self.storedDestination
        // Anything else that writes the destination shows up here: the group
        // picker's Play writes it directly, and the share extension writes it
        // between launches. Same shape as `HardwareVolumeService`'s route
        // watcher — the tasks inherit this actor, so `refresh` runs on it.
        for name in [UserDefaults.didChangeNotification, UIApplication.willEnterForegroundNotification] {
            observers.append(Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    self?.refresh()
                }
            })
        }
        observers.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: SonosService.availabilityDidChange) {
                self?.speakersCameOrWent()
            }
        })
    }

    /// The remembered destination, or this device while no speaker can be
    /// reached: Sonos switched off, or the phone on cellular. The speaker
    /// stays remembered for when they're back.
    private static var storedDestination: PlayDestination {
        guard SonosService.shared.isAvailable else { return .device }
        return PlayDestination.remembered ?? .device
    }

    /// Re-reads the stored destination. Only writes when it changed, so the
    /// (frequent) defaults notification doesn't churn observers.
    func refresh() {
        let stored = Self.storedDestination
        if stored != destination {
            destination = stored
            // The play call sites short-circuit to this; see `remember`.
            SelectedGroupService.shared.group = group
        }
    }

    /// The phone left Wi‑Fi or came back to it. Away, the route reads as
    /// this device. Back, it returns to the remembered speaker, unless this
    /// device is playing: then it stays here, rather than the player
    /// jumping to a speaker that isn't playing what's heard.
    private func speakersCameOrWent() {
        if SonosService.shared.isAvailable, destination == .device,
           LocalPlaybackService.shared.isPlaying, PlayDestination.remembered?.groupID != nil {
            Self.log.notice("speakers back, but this device is playing: staying here")
            PlayDestination.device.remember()
        }
        refresh()
    }

    /// The live group for a speaker destination. `nil` for the device, and
    /// for a remembered group that has since gone — resolved on every read so
    /// a topology refresh, which replaces every `GroupRoom`, can't leave a
    /// stale instance behind.
    var group: GroupRoom? {
        guard let id = destination.groupID else { return nil }
        return SonosService.shared.groups.first { $0.coordinatorID == id }
    }

    // MARK: - Controllers

    /// What plays at the route: where transport, the queue and the volume go.
    var controller: any PlaybackController {
        controller(for: destination)
    }

    /// The route the player surfaces show: the source while a hand-off holds
    /// it (see `hold`), else the route itself.
    var presentedDestination: PlayDestination {
        hold?.source ?? destination
    }

    /// What the player, the mini player and the queue panel draw, and what
    /// their controls act on. While a hand-off holds the player, the source
    /// as `HeldPlaybackController` sees it: the song it was playing, the
    /// hold's word on playing and position, and nothing to press.
    var presented: any PlaybackController {
        guard let hold else { return controller(for: destination) }
        return HeldPlaybackController(source: controller(for: hold.source), hold: hold)
    }

    /// The group `presented` is, for the extras only a speaker has.
    var presentedGroup: GroupRoom? {
        presented.group
    }

    /// A hand-off is under way and the player is holding on its source.
    var isHolding: Bool {
        hold != nil
    }

    /// The group being heard, where the hardware volume buttons go: the held
    /// source until the hand-off stops it, the route's from then on. Nil
    /// for this device.
    var audibleGroup: GroupRoom? {
        guard let hold, !hold.sourceStopped else { return group }
        return controller(for: hold.source).group
    }

    /// The controller for `destination`. A speaker that isn't among the
    /// groups — not found yet at launch, or gone — reads as this device, as
    /// the player always has: there is nothing of the speaker's to show.
    func controller(for destination: PlayDestination) -> any PlaybackController {
        guard let id = destination.groupID,
              SonosService.shared.groups.contains(where: { $0.coordinatorID == id }) else {
            return LocalPlaybackService.shared
        }
        return SonosGroupController(coordinatorID: id)
    }

    // MARK: - Switching

    /// Points playback at `target` and carries whatever is playing across.
    ///
    /// The destination is remembered at once — the button's checkmark and
    /// the accessory follow immediately — and the hand-off runs behind it.
    /// Nothing playing at the source means there is nothing to carry: the
    /// next Play goes to the new destination, which is all the route button
    /// used to do.
    ///
    /// `carrying: false` moves only the route. The device's queue is parked
    /// rather than left playing under a speaker the player now shows; a
    /// speaker being left is left alone, playing its own queue.
    func switchTo(_ target: PlayDestination, carrying: Bool = true) {
        guard target != destination else { return }

        let source = group
        // Whether the phone is what's playing now. Decided by the route, not
        // by whether the local queue has anything in it: a parked queue is
        // still there under a speaker route, and mustn't be carried onto the
        // next speaker chosen in place of that speaker's own queue.
        let fromDevice = destination == .device
        // What the player shows now, and whether to keep showing it through
        // the hand-off: only when a queue will actually come across.
        let shown = presented
        let holds = carrying && shown.destination != target && hasSomethingToCarry(to: target)
        let targetGroup: GroupRoom?
        switch target {
        case .device:
            targetGroup = nil
        case let .group(id):
            guard let found = SonosService.shared.groups.first(where: { $0.coordinatorID == id }) else {
                Self.log.error("route → \(id, privacy: .public): group is gone")
                AlertService.shared.showAlert(with: "That speaker isn't available right now", imageName: "hifispeaker.slash")
                return
            }
            targetGroup = found
        }
        remember(target)

        guard carrying else {
            handoffTask?.cancel()
            switchToken += 1
            isSwitching = false
            endHold()
            if fromDevice {
                LocalPlaybackService.shared.park()
            }
            Self.log.notice("route → \(targetGroup?.nameWithCount ?? "device", privacy: .public): switched without carrying")
            return
        }

        handoffTask?.cancel()
        switchToken += 1
        let token = switchToken
        isSwitching = true
        // A switch made during another's hold keeps that one: its source is
        // already on its way out, so a fresh read of it would say paused.
        let newHold = hold ?? Hold(
            source: shown.destination,
            wasPlaying: shown.isPlaying,
            position: shown.position(),
            since: .now,
            isClockRunning: shown.isPlaying
        )
        beginHold(holds ? newHold : nil)
        handoffTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.switchToken == token {
                    self.isSwitching = false
                    // Nothing came across — nothing to carry, or a failure
                    // put the route back — so the player shows the route as
                    // it now stands. A hand-off that landed has passed the
                    // hold to `releaseHold(whenShowing:on:)` already.
                    if self.holdRelease == nil {
                        self.endHold()
                    }
                }
            }
            if let targetGroup {
                await self.handOffToGroup(targetGroup, from: source, fromDevice: fromDevice)
            } else {
                await self.handOffToDevice(from: source)
            }
        }
    }

    /// Reads every other speaker's transport source ahead of a pick, so the
    /// hand-off to whichever is chosen starts with its first real call. Run
    /// when the Play On sheet opens; nothing waits on it, and a hand-off that
    /// finds no fresh read makes its own.
    func prefetchTargets() {
        let sonos = SonosService.shared
        guard sonos.isAvailable else { return }
        let targets = sonos.groups
            .filter { $0.coordinatorID != destination.groupID }
            .map { (id: $0.coordinatorID, ip: $0.ip) }
        guard !targets.isEmpty else { return }
        prefetchTask?.cancel()
        prefetchTask = Task { [weak self] in
            await withTaskGroup(of: (String, PlaybackService?).self) { taskGroup in
                for target in targets {
                    taskGroup.addTask {
                        (target.id, await sonos.playbackService(ip: target.ip))
                    }
                }
                for await (id, service) in taskGroup {
                    guard let service, !Task.isCancelled else { continue }
                    self?.prefetched[id] = (service, .now)
                }
            }
        }
    }

    /// The sheet-time read for `group` if it's still fresh, used once: the
    /// hand-off is about to change the speaker's source itself.
    private func takePrefetched(_ group: GroupRoom) -> PlaybackService? {
        guard let entry = prefetched.removeValue(forKey: group.coordinatorID),
              Date.now.timeIntervalSince(entry.at) < Self.prefetchLifetime else { return nil }
        return entry.service
    }

    /// Whether switching to `target` would have something to carry, read
    /// off cached state so it can decide at once whether to ask. Only a
    /// queue carries: a speaker on radio, TV or a line-in doesn't count.
    func hasSomethingToCarry(to target: PlayDestination) -> Bool {
        guard target != destination else { return false }
        if destination == .device {
            return localSnapshot() != nil
        }
        guard let source = group, source.coordinatorID != target.groupID else { return false }
        // `.unknown` is a cache not yet filled in, not a radio: ask, and
        // let the hand-off's fetch settle it.
        return [.queue, .unknown].contains(source.playbackService) && !source.coordinatorRoom.track.isEmpty
    }

    /// Re-points a speaker route at another coordinator with no hand-off.
    /// A regroup that promoted a different room moved the queue with it on
    /// the speaker side, so there is nothing to carry; the player just
    /// follows the group to its new coordinator.
    func follow(groupID: String) {
        guard destination.groupID != groupID else { return }
        remember(.group(groupID))
    }

    private func remember(_ target: PlayDestination) {
        destination = target
        target.remember()
        // The play call sites short-circuit to this when it holds a group, so
        // it has to agree with the route or a stale group outranks the device.
        SelectedGroupService.shared.group = group
        if let id = target.groupID {
            Router.main.selectedID = id
        }
    }

    /// Puts the route back on the source after a hand-off that failed, so
    /// the player follows what is actually playing. Only while the route is
    /// still the failed target: a choice made since is left alone.
    private func revert(from target: PlayDestination, to source: PlayDestination?) {
        guard let source, destination == target, !Task.isCancelled else { return }
        Self.log.notice("route: hand-off failed, back to \(source.groupID ?? "device", privacy: .public)")
        remember(source)
    }

    // MARK: - Holding the player on the source

    /// Starts showing `hold` in the route's place, or stops holding.
    ///
    /// Bounded by `holdLimit` from here, and by `holdTimeout` from when the
    /// source stops (`armHoldWatchdog(after:)`): past either the player shows
    /// the route as it stands, whatever the hand-off is doing — a speaker
    /// that never answers shouldn't leave the player showing a source that
    /// has gone quiet.
    ///
    /// A switch made during another's hold passes that hold back in, and
    /// keeps its deadline.
    private func beginHold(_ new: Hold?) {
        let deadline = new != nil && new == hold ? holdDeadline : nil
        endHold()
        guard let new else { return }
        hold = new
        holdDeadline = deadline ?? ContinuousClock.now.advanced(by: Self.holdLimit)
        armHoldWatchdog(after: Self.holdLimit)
    }

    /// (Re)starts the hold's limit, `after` from now but never past
    /// `holdDeadline`.
    private func armHoldWatchdog(after limit: Duration) {
        guard hold != nil else { return }
        holdWatchdog?.cancel()
        var deadline = ContinuousClock.now.advanced(by: limit)
        if let holdDeadline, holdDeadline < deadline {
            deadline = holdDeadline
        }
        let token = switchToken
        holdWatchdog = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled, let self, self.switchToken == token, self.hold != nil else { return }
            Self.log.notice("route: hand-off still running at the hold's limit; the player follows the route")
            self.endHold()
        }
    }

    // The hand-off's own calls on the hold. Each is a no-op once a newer
    // switch has cancelled the hand-off: the hold then belongs to that
    // switch, which may have taken it over (see `switchTo`).

    /// Keeps the bars in step with what's heard while the hold lasts: stopped
    /// at `position` while neither end is playing, running from it once the
    /// target is. The play button keeps reading as the source did.
    private func setHoldClock(_ position: TimeInterval, running: Bool) {
        guard !Task.isCancelled, var hold else { return }
        hold.position = position
        hold.since = .now
        hold.isClockRunning = running
        self.hold = hold
    }

    /// The hand-off has stopped the source: nothing is heard from it any
    /// more, so the volume buttons go to the target, and the hold now waits
    /// only on the target, for `holdTimeout` at most.
    private func noteSourceStopped() {
        guard !Task.isCancelled, var hold else { return }
        hold.sourceStopped = true
        self.hold = hold
        armHoldWatchdog(after: Self.holdTimeout)
    }

    /// The hand-off is done with the hold: the player follows the route.
    private func handOffEndsHold() {
        guard !Task.isCancelled else { return }
        endHold()
    }

    private func endHold() {
        holdRelease?.cancel()
        holdRelease = nil
        holdWatchdog?.cancel()
        holdWatchdog = nil
        holdDeadline = nil
        if hold != nil {
            hold = nil
        }
    }

    /// Lets the player go over to `target` once the speaker names the
    /// carried song and its cover is in memory, so the swap lands on the
    /// same song, already drawn — not on the speaker's last track, or on an
    /// empty cover while this one loads. A speaker reports the new item a
    /// beat after it starts it, and the item's artwork a beat after that.
    ///
    /// Bounded by `holdSettleLimit`: a speaker that names the song another
    /// way, or a cover that won't load, still lets go. Unstructured, so the
    /// tail filling in behind the first song doesn't wait on it.
    private func releaseHold(whenShowing item: PlayableContent, on target: GroupRoom) {
        guard !Task.isCancelled, hold != nil else { return }
        let token = switchToken
        let coordinatorID = target.coordinatorID
        holdRelease?.cancel()
        holdRelease = Task { [weak self] in
            let sonos = SonosService.shared
            let deadline = ContinuousClock.now.advanced(by: Self.holdSettleLimit)
            // The socket brings the new item when something is listening;
            // with the player closed nothing may be, so after a moment the
            // track is read once.
            let refreshAt = ContinuousClock.now.advanced(by: .seconds(1))
            var refreshed = false
            var warmed: Set<URL> = []
            while ContinuousClock.now < deadline, !Task.isCancelled {
                guard let group = sonos.groups.first(where: { $0.coordinatorID == coordinatorID }) else { break }
                let track = group.coordinatorRoom.track
                if Self.track(track, isShowing: item) {
                    // No URL yet is the cover still on its way rather than a
                    // song without one; the deadline covers the second case.
                    if let url = track.artworkURL, let request = track.playerArtworkRequest {
                        if ImagePipeline.shared.cache.cachedImage(for: request, caches: .memory) != nil {
                            break
                        }
                        // The request `ArtworkView` makes, so the cover lands
                        // in the entry the player reads on its first frame.
                        if warmed.insert(url).inserted {
                            Task { _ = try? await ImagePipeline.shared.image(for: request) }
                        }
                    }
                } else if !refreshed, ContinuousClock.now >= refreshAt {
                    refreshed = true
                    try? await sonos.updateTrackInformation(for: [group])
                    continue
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled, let self, self.switchToken == token else { return }
            self.holdRelease = nil
            self.endHold()
        }
    }

    /// The speaker has stopped at `position` and this device is about to arm
    /// the song there: the bars wait at that spot, and the hold's limit runs
    /// from now. The hold ends once the device is going (see the callers):
    /// arming starts the clock at 0:00 and goes through a moment of not
    /// playing, which the player shouldn't show.
    private func holdUntilDeviceStarts(at position: TimeInterval) {
        setHoldClock(position, running: false)
        noteSourceStopped()
    }

    /// Whether the speaker's `track` is `item`: by title, which survives the
    /// trip through any service, or by the id the item went out with — as a
    /// whole part of the track's id, so a short Plex or Subsonic id can't
    /// match the middle of the previous track's.
    private static func track(_ track: Track, isShowing item: PlayableContent) -> Bool {
        guard !track.isEmpty, !track.isSkipPreview else { return false }
        if !item.title.isEmpty, track.song.localizedCaseInsensitiveCompare(item.title) == .orderedSame {
            return true
        }
        let id = item.content.id
        return !id.isEmpty && contains(track.trackID, wholePart: id)
    }

    /// Whether `part` occurs in `string` with no letter or digit either side.
    private static func contains(_ string: String, wholePart part: String) -> Bool {
        func isEdge(_ character: Character?) -> Bool {
            guard let character else { return true }
            return !(character.isLetter || character.isNumber)
        }
        var searchStart = string.startIndex
        while searchStart < string.endIndex,
              let found = string.range(of: part, range: searchStart..<string.endIndex) {
            let before = found.lowerBound > string.startIndex ? string[string.index(before: found.lowerBound)] : nil
            let after = found.upperBound < string.endIndex ? string[found.upperBound] : nil
            if isEdge(before), isEdge(after) {
                return true
            }
            searchStart = string.index(after: found.lowerBound)
        }
        return false
    }

    // MARK: - Snapshots

    /// What's playing at a source, enough to pick it up somewhere else: the
    /// queue from the current track on, and how far into that track it is.
    /// The tracks already played stay behind — carrying them would put the
    /// first note on the new target behind every one of them being queued.
    private struct Snapshot {
        var items: [PlayableContent]
        /// Seconds into `items[0]`.
        var position: TimeInterval
        var isPlaying: Bool
        /// The speaker's 1-based queue position of `items[0]`; nil for the
        /// device. Lets a later read of the speaker be matched to this track.
        var queuePosition: Int?
    }

    private func localSnapshot() -> Snapshot? {
        let playback = LocalPlaybackService.shared
        guard playback.isActive, let current = playback.nowPlaying else { return nil }
        return Snapshot(items: [current] + playback.upNext, position: playback.progress, isPlaying: playback.isPlaying)
    }

    /// Only a queue can be carried across — radio, TV and a line-in have
    /// nothing to hand over, so those come back `nil` and the speaker keeps
    /// going.
    ///
    /// Everything is fetched rather than read off the cached room: after
    /// backgrounding, or with the group not the one being listened to, the
    /// cache lags the device — a stale "paused" left the speaker playing
    /// under the phone, and a stale position started the phone in the wrong
    /// place. Same reason `seek(trackNumber:)` fetches.
    private func snapshot(of group: GroupRoom) async -> Snapshot? {
        let sonos = SonosService.shared
        let service = await sonos.playbackService(ip: group.ip) ?? group.playbackService
        // Kept, so a caller can say what it was that couldn't be carried.
        group.playbackService = service
        guard service == .queue else { return nil }
        let queue = await sonos.getQueue(ip: group.ip)
        guard !queue.isEmpty else { return nil }
        let fetched = await sonos.getTrack(ip: group.ip)
        let state = await sonos.getPlaybackInfo(ip: group.ip)
        // The cached track stands in when the read fails.
        let track = fetched ?? group.coordinatorRoom.track
        guard !track.isEmpty else { return nil }
        // Queue positions are 1-based; the current one is on the track.
        let start = queue.firstIndex { $0.metadata?.position == track.position }
            ?? max(0, min(track.position - 1, queue.count - 1))
        let isPlaying: Bool
        switch state {
        case .playing: isPlaying = true
        case .paused: isPlaying = false
        // Between states, or the read failed: the cache is the best guess.
        case .transitioning, .unknown: isPlaying = group.coordinatorRoom.isPlaying
        }
        return Snapshot(
            items: Array(queue[start...]),
            // Positions from the device are in milliseconds.
            position: (fetched?.playbackPosition ?? group.coordinatorRoom.estimatedPlaybackPosition()) / 1000,
            isPlaying: isPlaying,
            queuePosition: track.position
        )
    }

    // MARK: - To a speaker

    /// `fromDevice` says the phone was the route when the switch was made;
    /// only then is its queue the one to carry. Otherwise the source
    /// speaker's is, when there is one and it isn't the target.
    private func handOffToGroup(_ target: GroupRoom, from source: GroupRoom?, fromDevice: Bool) async {
        let sonos = SonosService.shared
        let began = ContinuousClock.now
        let snapshot: Snapshot?
        if fromDevice {
            snapshot = localSnapshot()
        } else if let source, source.coordinatorID != target.coordinatorID {
            snapshot = await self.snapshot(of: source)
        } else {
            snapshot = nil
        }

        guard let snapshot else {
            Self.log.notice("route → \(target.nameWithCount, privacy: .public): nothing playing to carry over")
            return
        }
        // When `snapshot.position` was true; a source still playing has
        // moved on from it by however long has passed since.
        let snapshotAt = ContinuousClock.now
        func step(_ what: String) {
            print("[handoff] \(Int(Self.seconds(ContinuousClock.now - began) * 1000))ms \(what)")
        }
        step("snapshot at \(String(format: "%.1f", snapshot.position))s, playing: \(snapshot.isPlaying)")

        // Files live in a folder on this device; no speaker can fetch them.
        let items = snapshot.items.filter { !$0.content.service.playsOnDeviceOnly }
        guard let first = items.first else {
            Self.log.notice("route → \(target.nameWithCount, privacy: .public): only device-only content queued")
            // Nothing moved, so the route doesn't either: the source plays on.
            revert(from: .group(target.coordinatorID), to: fromDevice ? .device : source.map { PlayDestination.group($0.coordinatorID) })
            AlertService.shared.showAlert(with: "Files on this device can't play on \(target.nameWithCount)", imageName: "exclamationmark.triangle")
            return
        }
        Self.log.notice("route → \(target.nameWithCount, privacy: .public): carrying \(items.count) items from \(fromDevice ? "device" : "speaker", privacy: .public) at \(Int(snapshot.position))s")

        // How the source comes down. The phone is parked, not stopped: its
        // queue stays, paused where it was, for the route coming back.
        var sourceStopped = false
        func stopSource() async {
            guard !sourceStopped else { return }
            sourceStopped = true
            if fromDevice {
                LocalPlaybackService.shared.park()
            } else if let source {
                await sonos.pause(ip: source.ip)
            }
            noteSourceStopped()
            step("source stopped")
        }

        // Overlapped: the source plays on until the speaker is heard, so the
        // switch has no silent gap, and the speaker starts far enough ahead
        // to meet it. Not near the end of the song (the source would move on
        // to the next one first) and not for anything that can't seek.
        let canSeek = first.content.type.isTrack
        // The item's own length when it carries one, else the source's.
        let length = first.metadata?.duration.map(Self.seconds)
            ?? (fromDevice ? LocalPlaybackService.shared.duration : (source?.coordinatorRoom.track.duration ?? 0) / 1000)
        let remaining: TimeInterval? = length > 0 ? length - snapshot.position : nil
        let overlap = canSeek && snapshot.isPlaying && (remaining ?? .infinity) > Self.overlapTailGuard
        let estimate = startupEstimates[target.coordinatorID] ?? Self.defaultStartup
        step("overlap: \(overlap), remaining: \(remaining.map { "\(Int($0))s" } ?? "unknown"), estimate: \(Int(estimate * 1000))ms")

        // Not overlapping, the phone comes down first as it always has; a
        // speaker source keeps playing until the target has started.
        if !overlap, fromDevice {
            await stopSource()
            setHoldClock(snapshot.position, running: false)
        }

        // The cached transport can be stale in the same way as above, and a
        // stale `.queue` would skip pointing the speaker at its queue. A read
        // taken as the menu opened is recent enough to stand in.
        if let service = takePrefetched(target) {
            target.playbackService = service
        } else {
            target.playbackService = await sonos.playbackService(ip: target.ip) ?? .unknown
        }
        step("transport read: \(target.playbackService)")
        guard !Task.isCancelled else { return }

        // Mid-song, the track is loaded at the offset before it starts (see
        // `SonosService.cue`), so the speaker buffers once. Anything that
        // can't seek, or a song barely begun and not overlapping, just starts.
        let cueing = canSeek && (overlap || snapshot.position > 2)
        var offset = snapshot.position
        var path = "from start"
        var startup: TimeInterval?

        do {
            if cueing {
                if overlap {
                    offset += Self.seconds(ContinuousClock.now - snapshotAt) + estimate
                }
                let landed = try await sonos.cue(first, on: target, at: offset)
                step("cued at \(String(format: "%.1f", offset))s, seek accepted: \(landed)")
                guard !Task.isCancelled else { return }
                if landed {
                    path = overlap ? "overlapped" : "seek first"
                    if snapshot.isPlaying {
                        // Unstructured, so it isn't cancelled under the wait:
                        // the wrapper holds its optimistic state for a beat
                        // after the command, and the wait shouldn't.
                        let playSent = ContinuousClock.now
                        let play = Task { await sonos.play(ip: target.ip) }
                        step("play sent")
                        if await sonos.waitUntilPlaying(ip: target.ip) {
                            startup = Self.seconds(ContinuousClock.now - playSent)
                            step("speaker playing")
                        } else {
                            step("speaker not playing after 4s")
                        }
                        // The speaker started at `offset` just now.
                        setHoldClock(offset, running: true)
                        // Speaker heard (or given up on): the source goes, even
                        // if a newer switch is on its way — leaving both
                        // playing would be the worse outcome.
                        await stopSource()
                        await play.value
                    }
                } else {
                    // Refused while stopped: start it and seek once it has
                    // the stream. The source stops first, so the speaker
                    // picks up where it actually stopped.
                    path = "fallback"
                    if overlap {
                        offset = snapshot.position + Self.seconds(ContinuousClock.now - snapshotAt)
                    }
                    await stopSource()
                    setHoldClock(offset, running: false)
                    await sonos.play(ip: target.ip)
                    let settled = await sonos.waitUntilSettled(ip: target.ip)
                    step("fallback: settled as \(settled)")
                    guard !Task.isCancelled else { return }
                    await sonos.seek(to: offset * 1000, on: target)
                    setHoldClock(offset, running: snapshot.isPlaying)
                    step("fallback: seeked to \(String(format: "%.1f", offset))s")
                    if !snapshot.isPlaying {
                        await sonos.pause(ip: target.ip)
                    }
                }
                // Held there until the speaker reports playing past it, as
                // for any seek (see `Room.beginSeek`).
                target.coordinatorRoom.beginSeek(to: offset * 1000)
            } else {
                // The first track alone, so it starts now; the rest fill in
                // behind it while it plays. One call for the lot meant the
                // first note waited on every AddURIToQueue round trip.
                try await sonos.queue(contents: [first], group: target, position: .replace, startIndex: 0)
                setHoldClock(0, running: snapshot.isPlaying)
                step("queued and started from the top")
                if !snapshot.isPlaying {
                    await sonos.pause(ip: target.ip)
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            Self.log.error("route → \(target.nameWithCount, privacy: .public): replace failed: \(error.localizedDescription, privacy: .public)")
            if fromDevice, sourceStopped {
                await restoreLocal(snapshot)
            }
            guard !Task.isCancelled else { return }
            // The source is playing again (or never stopped), so the route
            // goes back to it — left on the speaker, the player showed a
            // speaker that wasn't playing over a phone that was.
            revert(from: .group(target.coordinatorID), to: fromDevice ? .device : source.map { PlayDestination.group($0.coordinatorID) })
            AlertService.shared.showAlert(with: "Couldn't move playback to \(target.nameWithCount)", imageName: "exclamationmark.triangle")
            return
        }
        // A newer switch may be going back to a speaker source; leave it be.
        guard !Task.isCancelled else { return }
        await stopSource()

        if let startup {
            // Weighted toward the latest: a speaker's own time varies with
            // the service and the network, and one slow start shouldn't
            // set the next overlap a second ahead.
            let blended = (startupEstimates[target.coordinatorID].map { ($0 + startup) / 2 }) ?? startup
            startupEstimates[target.coordinatorID] = min(max(blended, 0.2), 3)
        }
        let total = Int(Self.seconds(ContinuousClock.now - began) * 1000)
        let startupText = startup.map { "\(Int($0 * 1000))ms" } ?? "-"
        print("[handoff] → \(target.nameWithCount): started in \(total)ms (\(path)), play→playing \(startupText), estimate was \(Int(estimate * 1000))ms")

        AlertService.shared.showAlertContent(
            with: first,
            subtitle: "Now playing on \(target.nameWithCount)",
            symbolName: "hifispeaker.fill"
        )

        // Playing now: the switch is done as far as the UI is concerned. The
        // tail fills in behind it, and a further switch cancels that.
        guard !Task.isCancelled else { return }
        isSwitching = false
        releaseHold(whenShowing: first, on: target)

        let rest = Array(items.dropFirst())
        guard !rest.isEmpty else { return }
        do {
            try await sonos.queue(contents: rest, group: target, position: .end)
        } catch {
            guard !Task.isCancelled else { return }
            // Playing already; the tail is what's missing.
            Self.log.error("route → \(target.nameWithCount, privacy: .public): tail failed: \(error.localizedDescription, privacy: .public)")
            AlertService.shared.showAlert(with: "Some of the queue couldn't be added on \(target.nameWithCount)", imageName: "exclamationmark.triangle")
        }
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let (seconds, attoseconds) = duration.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }

    /// Picks the parked queue back up where `park()` left it — the same
    /// queue, not the snapshot's tail, so the tracks already played are still
    /// behind the current one.
    private func restoreLocal(_ snapshot: Snapshot) async {
        let playback = LocalPlaybackService.shared
        do {
            try await playback.resumeCurrent()
            if !snapshot.isPlaying {
                playback.pause()
            }
        } catch {
            Self.log.error("restore on device failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - To this device

    /// The AirPlay half in this direction: the speaker stops the moment the
    /// route moves, and the device picks the track up at the second the
    /// speaker stopped on.
    ///
    /// Two ways back. If the speaker is still on the queue the phone parked
    /// when it took over (see `LocalPlaybackService.park()`), that queue is
    /// picked up in place — played tracks and all, with no lookups. Otherwise
    /// the speaker's queue comes across: the first track starts at once and
    /// the rest fill in behind it, the mirror of the speaker-bound direction.
    private func handOffToDevice(from source: GroupRoom?) async {
        guard let source else { return }
        let sonos = SonosService.shared
        guard var snapshot = await snapshot(of: source) else {
            guard !Task.isCancelled else { return }
            // A radio station, the TV or a line-in can't be carried, and
            // saying nothing left the route on the device with the speaker
            // playing on — which read as the switch having done nothing.
            // Fetched: the cached state is what a stale poll left there.
            if await sonos.getPlaybackInfo(ip: source.ip) == .playing {
                let service = source.playbackService
                let what = [.radio, .tv, .lineIn, .airplay, .spotifyConnect].contains(service) ? service.title : "What's playing"
                Self.log.notice("route → device: \(service.title, privacy: .public) on \(source.nameWithCount, privacy: .public) can't be carried over")
                AlertService.shared.showAlert(with: "\(what) on \(source.nameWithCount) can't play on this device", imageName: "iphone.slash")
            } else {
                Self.log.notice("route → device: nothing on \(source.nameWithCount, privacy: .public) to carry over")
            }
            return
        }
        guard !Task.isCancelled else { return }

        let playback = LocalPlaybackService.shared

        if let index = parkedIndex(matching: snapshot) {
            snapshot.position = await stop(source, holding: snapshot)
            guard !Task.isCancelled else { return }
            holdUntilDeviceStarts(at: snapshot.position)
            Self.log.notice("route → device: picking the parked queue back up at \(index) from \(source.nameWithCount, privacy: .public) at \(Int(snapshot.position))s")
            do {
                try await playback.resume(at: index, from: snapshot.position)
            } catch {
                Self.log.error("route → device: resume failed: \(error.localizedDescription, privacy: .public)")
                if snapshot.isPlaying {
                    await sonos.play(ip: source.ip)
                }
                revert(from: .device, to: .group(source.coordinatorID))
                AlertService.shared.showAlert(with: error.localizedDescription, imageName: "exclamationmark.triangle")
                return
            }
            if !snapshot.isPlaying {
                playback.pause()
            }
            // Armed and going: the player comes over onto the song the
            // speaker stopped on, at its spot. Before the arm, the device was
            // still on the parked track, or at 0:00 while it loaded.
            handOffEndsHold()
            if let current = playback.nowPlaying {
                AlertService.shared.showAlertContent(
                    with: current,
                    subtitle: "Now playing on this device",
                    symbolName: "iphone.radiowaves.left.and.right"
                )
            }
            return
        }

        // The first row the device can take, looked up if it has to be —
        // on its own, so the first note doesn't wait on a long queue's
        // lookups. The rest follow once it's playing. Bounded: a server
        // that answers nothing shouldn't be asked about every row.
        var first: PlayableContent?
        var firstIndex = 0
        for (index, item) in snapshot.items.prefix(Self.firstTrackAttempts).enumerated() {
            guard !Task.isCancelled else { return }
            if let local = await localItem(item) {
                first = local
                firstIndex = index
                break
            }
        }
        guard let first else {
            Self.log.notice("route → device: nothing in the first \(min(snapshot.items.count, Self.firstTrackAttempts)) rows on \(source.nameWithCount, privacy: .public) can play here")
            AlertService.shared.showAlert(with: "Nothing playing on \(source.nameWithCount) can play on this device", imageName: "iphone.slash")
            return
        }

        snapshot.position = await stop(source, holding: snapshot)
        guard !Task.isCancelled else { return }
        holdUntilDeviceStarts(at: snapshot.position)
        Self.log.notice("route → device: carrying \(snapshot.items.count - firstIndex) items from \(source.nameWithCount, privacy: .public) at \(Int(snapshot.position))s")

        // The position is the current track's; with that one dropped the
        // next starts from its top. Under a couple of seconds is the start
        // of the track as far as anyone can tell.
        let position = firstIndex == 0 && snapshot.position > 2 ? snapshot.position : nil
        do {
            // The position goes in with the play so the first note heard
            // is the one the speaker stopped on.
            try await playback.play([first], from: position)
        } catch {
            Self.log.error("route → device: play failed: \(error.localizedDescription, privacy: .public)")
            if snapshot.isPlaying {
                await sonos.play(ip: source.ip)
            }
            revert(from: .device, to: .group(source.coordinatorID))
            AlertService.shared.showAlert(with: error.localizedDescription, imageName: "exclamationmark.triangle")
            return
        }
        if !snapshot.isPlaying {
            playback.pause()
        }
        // As in the parked case: armed, so the player comes over.
        handOffEndsHold()

        AlertService.shared.showAlertContent(
            with: first,
            subtitle: "Now playing on this device",
            symbolName: "iphone.radiowaves.left.and.right"
        )

        // Playing now: the switch is done as far as the UI is concerned. The
        // tail fills in behind it, and a further switch cancels that.
        guard !Task.isCancelled else { return }
        isSwitching = false

        let pending = Array(snapshot.items.dropFirst(firstIndex + 1))
        let rest = await localItems(pending)
        guard !Task.isCancelled else { return }
        if rest.count < pending.count {
            Self.log.error("route → device: \(pending.count - rest.count) of the queue couldn't be fetched")
            AlertService.shared.showAlert(with: "Some of the queue couldn't be added on this device", imageName: "exclamationmark.triangle")
        }
        guard !rest.isEmpty else { return }
        do {
            try await playback.addToQueue(rest)
        } catch {
            Self.log.error("route → device: tail failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// How many leading rows are tried for the first track before giving up.
    private static let firstTrackAttempts = 20

    /// Stops the speaker and returns the exact second it stopped on. Not
    /// gated on the snapshot's state: a pause on a paused speaker is a
    /// no-op, and a wrong "paused" is what used to leave it playing under
    /// the phone. The snapshot's position was read while the speaker was
    /// still going, and the queue fetch alone puts it a moment behind; the
    /// frozen one is taken only while it is still the same track, since it
    /// could have run onto the next one in between.
    private func stop(_ source: GroupRoom, holding snapshot: Snapshot) async -> TimeInterval {
        let sonos = SonosService.shared
        await sonos.pause(ip: source.ip)
        guard !Task.isCancelled else { return snapshot.position }
        if let frozen = await sonos.getTrack(ip: source.ip), frozen.position == snapshot.queuePosition {
            return frozen.playbackPosition / 1000
        }
        return snapshot.position
    }

    /// A speaker queue row as the device can take it, or nil. Apple rows
    /// come off the speaker ready; Plex and Subsonic rows come off it with
    /// only their id — the stream URL the local player needs isn't in the
    /// queue's DIDL — so those are looked up on their server again, which
    /// is what let a queue go to a speaker and not come back.
    private func localItem(_ item: PlayableContent) async -> PlayableContent? {
        let playback = LocalPlaybackService.shared
        if playback.canPlayLocally(item) { return item }
        guard item.content.type == .track, [.plex, .subsonic].contains(item.content.service) else { return nil }
        guard let resolved = await SonosService.shared.contentLookup(id: item.content.id, type: .track, service: item.content.service) else {
            return nil
        }
        return playback.canPlayLocally(resolved) ? resolved : nil
    }

    /// `items` as the device can take them, in order, dropping what it
    /// can't. The lookups run a few at a time: a long Plex queue fired at
    /// a home server all at once is how you get throttled.
    private func localItems(_ items: [PlayableContent]) async -> [PlayableContent] {
        guard !items.isEmpty else { return [] }
        let maxInFlight = 4
        var resolved = [PlayableContent?](repeating: nil, count: items.count)
        await withTaskGroup(of: (Int, PlayableContent?).self) { group in
            var next = 0
            while next < min(maxInFlight, items.count) {
                let index = next
                group.addTask { (index, await self.localItem(items[index])) }
                next += 1
            }
            for await (index, item) in group {
                resolved[index] = item
                guard !Task.isCancelled, next < items.count else { continue }
                let pending = next
                group.addTask { (pending, await self.localItem(items[pending])) }
                next += 1
            }
        }
        return resolved.compactMap { $0 }
    }

    // MARK: - The parked queue

    /// Where in the phone's parked queue the speaker's current track is, when
    /// the speaker is still playing exactly what the phone handed over: the
    /// same rows from that track to the end. Anything added, removed or
    /// reordered on the speaker since means the speaker's queue is the newer
    /// one, and this is `nil` so it comes across instead.
    private func parkedIndex(matching snapshot: Snapshot) -> Int? {
        let parked = LocalPlaybackService.shared.queue
        guard let current = snapshot.items.first, !parked.isEmpty else { return nil }
        let currentKey = Self.carryKey(for: current)
        // The rows the speaker was given: device-only files stayed behind.
        let carried = parked.enumerated().filter { !$0.element.content.service.playsOnDeviceOnly }
        guard let start = carried.firstIndex(where: { Self.carryKey(for: $0.element) == currentKey }) else { return nil }
        let tail = carried[start...]
        guard tail.count == snapshot.items.count else { return nil }
        for (parkedRow, speakerRow) in zip(tail, snapshot.items)
        where Self.carryKey(for: parkedRow.element) != Self.carryKey(for: speakerRow) {
            return nil
        }
        return tail.first?.offset
    }

    /// Identity that survives the round trip through a speaker's queue. Rows
    /// parsed back off a speaker carry the same service and id the phone sent,
    /// bar Plex, whose id comes back without the percent-encoding it went out
    /// with — the rating key at the end is what's compared there.
    private static func carryKey(for item: PlayableContent) -> String {
        var id = item.content.id
        if item.content.service == .plex {
            id = id.removingPercentEncoding?.components(separatedBy: ":").last ?? id
        }
        return "\(item.content.service):\(id)"
    }
}

/// What a route switch does with what's playing. Set in Settings › Playback
/// and by "Don't ask again" on the switch's prompt.
enum QueueTransferPreference: String, CaseIterable, Identifiable {
    case ask
    case always
    case never

    var id: String { rawValue }

    static var current: QueueTransferPreference {
        UserDefaults.standard.string(forKey: AppStorageKeys.routeQueueTransfer)
            .flatMap(QueueTransferPreference.init(rawValue:)) ?? .ask
    }

    var title: String {
        switch self {
        case .ask: "Ask"
        case .always: "Move"
        case .never: "Don't Move"
        }
    }

    var footnote: String {
        switch self {
        case .ask: "Asks each time whether to bring what's playing along."
        case .always: "What's playing always moves to where you switch."
        case .never: "Switching only changes where the next Play goes."
        }
    }
}
