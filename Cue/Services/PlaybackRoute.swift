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
        case .transitioning: isPlaying = group.coordinatorRoom.isPlaying
        }
        return Snapshot(
            items: Array(queue[start...]),
            // Positions from the device are in milliseconds.
            position: (fetched?.playbackPosition ?? group.coordinatorRoom.playbackPosition) / 1000,
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

        // Take the phone down first so the two don't overlap — parked, not
        // stopped: its queue stays, paused where it was, for the route
        // coming back. Resumed below if the speaker refuses the content.
        if fromDevice {
            LocalPlaybackService.shared.park()
        }

        // The cached transport can be stale in the same way as above, and a
        // stale `.queue` would skip pointing the speaker at its queue.
        target.playbackService = await sonos.playbackService(ip: target.ip) ?? .unknown
        guard !Task.isCancelled else { return }

        do {
            // The first track alone, so it starts now; the rest fill in
            // behind it while it plays. One call for the lot meant the first
            // note waited on every AddURIToQueue round trip.
            try await sonos.queue(contents: [first], group: target, position: .replace, startIndex: 0)
        } catch {
            guard !Task.isCancelled else { return }
            Self.log.error("route → \(target.nameWithCount, privacy: .public): replace failed: \(error.localizedDescription, privacy: .public)")
            if fromDevice {
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
        guard !Task.isCancelled else { return }

        if snapshot.position > 2 {
            // Give the transport a moment to leave TRANSITIONING; a seek
            // landing before that is dropped.
            try? await Task.sleep(for: .milliseconds(600))
            await sonos.seek(to: snapshot.position * 1000, on: target)
            target.coordinatorRoom.playbackPosition = snapshot.position * 1000
        }
        if !snapshot.isPlaying {
            await sonos.pause(ip: target.ip)
        }
        if !fromDevice, let source {
            await sonos.pause(ip: source.ip)
        }

        AlertService.shared.showAlertContent(
            with: first,
            subtitle: "Now playing on \(target.nameWithCount)",
            symbolName: "hifispeaker.fill"
        )

        // Playing now: the switch is done as far as the UI is concerned. The
        // tail fills in behind it, and a further switch cancels that.
        guard !Task.isCancelled else { return }
        isSwitching = false

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
