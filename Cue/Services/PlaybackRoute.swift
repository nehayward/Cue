import Defaults
import Foundation
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
/// A long queue goes to a speaker a stretch at a time: the playing song and
/// the `feedAhead` after it, then more as the speaker plays toward the end of
/// what it has (see `Feed`).
///
/// Views read `destination` and `group` off `shared` rather than the
/// environment: the tab bar accessory and the Next Up panel are hosted
/// outside what `withEnvironments()` installs.
@MainActor
@Observable
final class PlaybackRoute {
    static let shared = PlaybackRoute()

    /// `log stream --predicate 'subsystem == "dance.cue" AND category == "route"' --level debug`
    private static let log = Logger(subsystem: "dance.cue", category: "route")

    /// The stored destination, mirrored so views can observe it.
    private(set) var destination: PlayDestination

    /// True from a switch until the target has started playing. The next
    /// stretch of the queue goes in after this clears, and the rest as the
    /// speaker plays (see `Feed`); the accessory shows it, and nothing is
    /// disabled by it — a second choice cancels the first.
    private(set) var isSwitching = false

    /// The hand-off in flight. A new choice cancels it: the URLSession calls
    /// under `SonosService` throw on cancellation, so a queue still filling in
    /// stops where it is rather than racing the next switch.
    @ObservationIgnored private var handoffTask: Task<Void, Never>?
    /// Bumped per switch, so a superseded hand-off's clean-up can't clear
    /// `isSwitching` for the one that replaced it.
    @ObservationIgnored private var switchToken = 0

    @ObservationIgnored private var observers: [Task<Void, Never>] = []

    /// Each speaker's transport source, read when the Play On menu opened,
    /// keyed by coordinator. Lets a hand-off picked from that menu skip the
    /// read it would otherwise make before the first note.
    @ObservationIgnored private var prefetched: [String: (service: PlaybackService, at: Date)] = [:]
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    /// Long enough to cover reading the menu and tapping; short enough that
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

    /// What each speaker is still owed of a queue carried to it, keyed by
    /// coordinator.
    @ObservationIgnored private var feeds: [String: Feed] = [:]
    @ObservationIgnored private var feedToken = 0
    /// How many rows a speaker is kept ahead of the one playing.
    private static let feedAhead = 50
    /// With fewer than this left after the playing row, the speaker is
    /// topped back up to `feedAhead`, so about ten go at a time.
    private static let feedLowWater = 40
    /// How often a speaker being fed is checked, against its cached place:
    /// nothing goes over the network unless that looks near the end.
    private static let feedInterval: Duration = .seconds(30)
    /// How long a feed goes on the cached place alone before asking the
    /// speaker, in case nothing is keeping that place current (a second
    /// group playing in the background, which the socket doesn't follow).
    private static let feedFallbackRead: Duration = .seconds(10 * 60)

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
    }

    /// The remembered destination, or this device while Sonos is switched
    /// off: a speaker remembered from before then can't be reached.
    private static var storedDestination: PlayDestination {
        guard SonosService.shared.isEnabled else { return .device }
        return PlayDestination.remembered ?? .device
    }

    /// Re-reads the stored destination. Only writes when it changed, so the
    /// (frequent) defaults notification doesn't churn observers.
    func refresh() {
        let stored = Self.storedDestination
        if stored != destination {
            destination = stored
        }
    }

    /// The live group for a speaker destination. `nil` for the device, and
    /// for a remembered group that has since gone — resolved on every read so
    /// a topology refresh, which replaces every `GroupRoom`, can't leave a
    /// stale instance behind.
    var group: GroupRoom? {
        guard let id = destination.groupID else { return nil }
        return SonosService.shared.groups.first { $0.coordinatorID == id }
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
        handoffTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.switchToken == token {
                    self.isSwitching = false
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
    /// when the Play On menu opens; nothing waits on it, and a hand-off that
    /// finds no fresh read makes its own.
    func prefetchTargets() {
        let sonos = SonosService.shared
        guard sonos.isEnabled else { return }
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

    /// The menu-time read for `group` if it's still fresh, used once: the
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
        // The queue moved with the group, and what it's still owed follows.
        if let old = destination.groupID, let feed = feeds.removeValue(forKey: old) {
            feed.task?.cancel()
            resumeFeed(feed, on: groupID)
        }
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
    ///
    /// `feed` is what a hand-off still owes this speaker; its rows follow the
    /// speaker's own while its queue is still the one carried.
    private func snapshot(of group: GroupRoom, feed: Feed? = nil) async -> Snapshot? {
        let sonos = SonosService.shared
        let service = await sonos.playbackService(ip: group.ip) ?? group.playbackService
        // Kept, so a caller can say what it was that couldn't be carried.
        group.playbackService = service
        guard service == .queue else { return nil }
        let queue = await sonos.getQueue(ip: group.ip)
        guard !queue.isEmpty else { return nil }
        // Read before the position, so its round trips aren't counted in
        // how far the source has moved on since.
        var owed: [PlayableContent] = []
        if let feed, let current = await reconciled(feed, with: group) {
            owed = current.pending
        }
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
            items: Array(queue[start...]) + owed,
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
        // How the source comes down: see `stopSource()` below.
        var sourceStopped = false
        // A speaker source being fed is held still while its queue is read,
        // and fed again if the hand-off leaves it playing.
        var sourceFeed: Feed?
        defer {
            if !sourceStopped, let source, let sourceFeed {
                resumeFeed(sourceFeed, on: source.coordinatorID)
            }
        }
        if fromDevice {
            snapshot = localSnapshot()
        } else if let source, source.coordinatorID != target.coordinatorID {
            sourceFeed = await stopFeed(source.coordinatorID)
            snapshot = await self.snapshot(of: source, feed: sourceFeed)
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
        func stopSource() async {
            guard !sourceStopped else { return }
            sourceStopped = true
            if fromDevice {
                LocalPlaybackService.shared.park()
            } else if let source {
                await sonos.pause(ip: source.ip)
            }
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

        // Its queue is about to be replaced, so whatever it was still owed
        // goes; waited out so none of it lands in the new queue.
        await stopFeed(target.coordinatorID)
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
                    await sonos.play(ip: target.ip)
                    let settled = await sonos.waitUntilSettled(ip: target.ip)
                    step("fallback: settled as \(settled)")
                    guard !Task.isCancelled else { return }
                    await sonos.seek(to: offset * 1000, on: target)
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

        // The next stretch now, and the rest as the speaker plays toward it.
        let rest = Array(items.dropFirst())
        let window = Array(rest.prefix(Self.feedAhead))
        guard let last = window.last else { return }
        do {
            try await sonos.queue(contents: window, group: target, position: .end)
        } catch {
            guard !Task.isCancelled else { return }
            // Playing already; the tail is what's missing.
            Self.log.error("route → \(target.nameWithCount, privacy: .public): tail failed: \(error.localizedDescription, privacy: .public)")
            AlertService.shared.showAlert(with: "Some of the queue couldn't be added on \(target.nameWithCount)", imageName: "exclamationmark.triangle")
            return
        }
        guard !Task.isCancelled else { return }
        // The queue was replaced with `first` alone, and the window followed.
        startFeed(Array(rest.dropFirst(window.count)), after: last, length: 1 + window.count, on: target)
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
        // Held still while the speaker's queue is read, and fed again unless
        // this device takes over.
        let sourceFeed = await stopFeed(source.coordinatorID)
        var handedOver = false
        defer {
            if !handedOver, let sourceFeed {
                resumeFeed(sourceFeed, on: source.coordinatorID)
            }
        }
        guard var snapshot = await snapshot(of: source, feed: sourceFeed) else {
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
            handedOver = true
            if !snapshot.isPlaying {
                playback.pause()
            }
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
        handedOver = true
        if !snapshot.isPlaying {
            playback.pause()
        }

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

    // MARK: - Feeding a speaker

    /// The rest of a queue carried to a speaker, sent as it plays toward it.
    ///
    /// Every row is its own AddURIToQueue round trip, so a long queue sent
    /// whole kept the speaker busy for minutes after the first note. A
    /// hand-off sends the playing row and the `feedAhead` after it, and the
    /// feed keeps the speaker about that far ahead.
    ///
    /// It runs as long as Cue does. In the background that's while
    /// `NowPlayingSessionService` holds the Lock Screen card for a playing
    /// speaker, whose silent audio keeps the app going (Cue Super, with the
    /// phone's audio on its own speaker), and its socket keeps that speaker's
    /// place current, so the checks cost nothing. Without the card the app is
    /// suspended: the speaker plays on through what it has and the feed
    /// catches up when Cue next runs. Quit, the speaker keeps what it was sent.
    private struct Feed {
        /// The rows not sent yet, in order.
        var pending: [PlayableContent]
        /// `carryKey` of the last row sent. While the speaker's queue still
        /// ends on it, the queue is the one carried and `pending` follows on;
        /// a Play or an Add to Queue since, from Cue or anywhere else, ends it
        /// on something else, and the feed stops.
        var lastSent: String
        /// The queue's length at the last read or send, which the cached
        /// place is measured against between reads. Rows added or removed
        /// since only move the next read earlier or later.
        var length: Int
        /// When the speaker was last asked, for `feedFallbackRead`.
        var checkedAt = ContinuousClock.now
        /// Tells a feed from one that replaced it on the same speaker.
        var token = 0
        var task: Task<Void, Never>?
    }

    /// Feeds `pending` to `group` behind `last`, the last row it was sent,
    /// with `length` rows in its queue.
    private func startFeed(_ pending: [PlayableContent], after last: PlayableContent, length: Int, on group: GroupRoom) {
        feeds.removeValue(forKey: group.coordinatorID)?.task?.cancel()
        resumeFeed(Feed(pending: pending, lastSent: Self.carryKey(for: last), length: length), on: group.coordinatorID)
    }

    /// Runs `feed` on the speaker `id`, unless something else feeds it by now.
    private func resumeFeed(_ feed: Feed, on id: String) {
        guard feeds[id] == nil, !feed.pending.isEmpty else { return }
        feedToken += 1
        let token = feedToken
        var feed = feed
        feed.token = token
        feed.task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.feedInterval)
                guard let self, !Task.isCancelled else { return }
                guard await self.topUp(id, token: token) else { break }
            }
            // Finished or given up. One that replaced it is left be.
            if let self, self.feeds[id]?.token == token {
                self.feeds[id] = nil
            }
        }
        feeds[id] = feed
    }

    /// Stops feeding the speaker `id` and hands back what it was still owed,
    /// once a top-up in flight has given up, so none of its rows land in a
    /// queue about to be replaced. A send cut off part-way is sorted out by
    /// `reconciled`.
    @discardableResult
    private func stopFeed(_ id: String) async -> Feed? {
        guard var feed = feeds.removeValue(forKey: id) else { return nil }
        feed.task?.cancel()
        await feed.task?.value
        feed.task = nil
        return feed
    }

    /// One check on a speaker being fed: with fewer than `feedLowWater` rows
    /// left after the playing one, it's topped back up to `feedAhead`.
    /// Returns false once the feed is over: everything sent, or the queue
    /// isn't the one carried any more.
    private func topUp(_ id: String, token: Int) async -> Bool {
        let sonos = SonosService.shared
        guard sonos.isEnabled, var stored = feeds[id], stored.token == token else { return false }
        // Not a coordinator just now (a regroup, a topology refresh): next time.
        guard let group = sonos.groups.first(where: { $0.coordinatorID == id }) else { return true }
        // The cached place first. The speaker is asked only when that looks
        // near the end, or when it hasn't been asked for a while. Queue
        // positions are 1-based, so this is the rows after the playing one.
        let cachedAhead = stored.length - group.coordinatorRoom.track.position
        guard cachedAhead < Self.feedLowWater || ContinuousClock.now - stored.checkedAt >= Self.feedFallbackRead else {
            return true
        }
        stored.checkedAt = ContinuousClock.now
        feeds[id] = stored

        guard let track = await sonos.getTrack(ip: group.ip),
              let length = try? await sonos.getQueueTotal(group: group) else { return true }
        // Shuffled, the speaker picks rows in any order, so the count after
        // the playing one says nothing about when it runs out: the rest goes.
        let shuffled = await sonos.playMode(ip: group.ip).isShuffleEnabled
        guard !Task.isCancelled else { return false }
        stored.length = length
        feeds[id] = stored
        let ahead = max(0, length - track.position)
        guard shuffled || ahead < Self.feedLowWater else { return true }

        // On the TV, a line-in or a station the queue waits underneath, and
        // adding to it would put the speaker back on it.
        guard let service = await sonos.playbackService(ip: group.ip), !Task.isCancelled else { return true }
        guard service == .queue else { return true }
        // Kept, so the add below doesn't point the speaker at its queue again.
        group.playbackService = service
        guard var current = await reconciled(stored, with: group) else {
            guard !Task.isCancelled else { return false }
            Self.log.notice("feed → \(group.nameWithCount, privacy: .public): the queue has changed; \(stored.pending.count) rows not sent")
            return false
        }
        guard !Task.isCancelled else { return false }
        guard !current.pending.isEmpty else { return false }

        let batch = Array(current.pending.prefix(shuffled ? current.pending.count : Self.feedAhead - ahead))
        do {
            try await sonos.queue(contents: batch, group: group, position: .end)
        } catch {
            guard !Task.isCancelled else { return false }
            Self.log.error("feed → \(group.nameWithCount, privacy: .public): failed: \(error.localizedDescription, privacy: .public)")
            AlertService.shared.showAlert(with: "Some of the queue couldn't be added on \(group.nameWithCount)", imageName: "exclamationmark.triangle")
            return false
        }
        guard !Task.isCancelled else { return false }
        current.pending.removeFirst(batch.count)
        current.lastSent = Self.carryKey(for: batch[batch.count - 1])
        current.length += batch.count
        feeds[id] = current
        Self.log.notice("feed → \(group.nameWithCount, privacy: .public): sent \(batch.count), \(current.pending.count) to go")
        return !current.pending.isEmpty
    }

    /// `feed` brought up to date with `group`'s queue: where the queue ends
    /// says how far the sending got, a send cut off part-way included. Nil
    /// when it ends on anything else — a Play or an Add to Queue, from Cue or
    /// another app, has made it someone else's queue.
    private func reconciled(_ feed: Feed, with group: GroupRoom) async -> Feed? {
        let sonos = SonosService.shared
        guard let length = try? await sonos.getQueueTotal(group: group), length > 0,
              let last = await sonos.getQueue(ip: group.ip, with: length - 1, total: 1).first else { return nil }
        let key = Self.carryKey(for: last)
        var feed = feed
        feed.length = length
        if key == feed.lastSent { return feed }
        guard let index = feed.pending.firstIndex(where: { Self.carryKey(for: $0) == key }) else { return nil }
        feed.lastSent = key
        feed.pending.removeFirst(index + 1)
        return feed
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
