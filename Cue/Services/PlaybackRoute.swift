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
        destination = PlayDestination.remembered ?? .device
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

    /// Re-reads the stored destination. Only writes when it changed, so the
    /// (frequent) defaults notification doesn't churn observers.
    func refresh() {
        let stored = PlayDestination.remembered ?? .device
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
    func switchTo(_ target: PlayDestination) {
        guard target != destination else { return }

        let source = group
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
                await self.handOffToGroup(targetGroup, from: source)
            } else {
                await self.handOffToDevice(from: source)
            }
        }
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

    private func handOffToGroup(_ target: GroupRoom, from source: GroupRoom?) async {
        let sonos = SonosService.shared
        let snapshot: Snapshot?
        let fromDevice: Bool
        if let local = localSnapshot() {
            snapshot = local
            fromDevice = true
        } else if let source, source.coordinatorID != target.coordinatorID {
            snapshot = await self.snapshot(of: source)
            fromDevice = false
        } else {
            snapshot = nil
            fromDevice = false
        }

        guard let snapshot else {
            Self.log.notice("route → \(target.nameWithCount, privacy: .public): nothing playing to carry over")
            return
        }

        // Files live in a folder on this device; no speaker can fetch them.
        let items = snapshot.items.filter { !$0.content.service.playsOnDeviceOnly }
        guard let first = items.first else {
            Self.log.notice("route → \(target.nameWithCount, privacy: .public): only device-only content queued")
            AlertService.shared.showAlert(with: "Files on this device can't play on \(target.nameWithCount)", imageName: "exclamationmark.triangle")
            return
        }
        Self.log.notice("route → \(target.nameWithCount, privacy: .public): carrying \(items.count) items from \(fromDevice ? "device" : "speaker", privacy: .public) at \(Int(snapshot.position))s")

        // Take the phone down first so the two don't overlap. Put back below
        // if the speaker refuses the content.
        if fromDevice {
            LocalPlaybackService.shared.stop()
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

    private func restoreLocal(_ snapshot: Snapshot) async {
        let playback = LocalPlaybackService.shared
        do {
            try await playback.play(snapshot.items, from: snapshot.position > 2 ? snapshot.position : nil)
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
    private func handOffToDevice(from source: GroupRoom?) async {
        guard let source else { return }
        guard var snapshot = await snapshot(of: source) else {
            Self.log.notice("route → device: nothing on \(source.nameWithCount, privacy: .public) to carry over")
            return
        }
        guard !Task.isCancelled else { return }

        let playback = LocalPlaybackService.shared
        let items = snapshot.items.filter { playback.canPlayLocally($0) }
        guard let first = items.first else {
            Self.log.notice("route → device: nothing on \(source.nameWithCount, privacy: .public) has a local backend")
            AlertService.shared.showAlert(with: "Nothing playing on \(source.nameWithCount) can play on this device", imageName: "iphone.slash")
            return
        }

        // Speaker down first, so the two don't overlap; resumed below if the
        // device can't take over. Not gated on the snapshot's state: a pause
        // on a paused speaker is a no-op, and a wrong "paused" is what used
        // to leave it playing under the phone.
        let sonos = SonosService.shared
        await sonos.pause(ip: source.ip)
        guard !Task.isCancelled else { return }

        // Frozen now, so this is the exact second to pick up from — the
        // snapshot's was read while the speaker was still going and the
        // queue fetch alone puts it a moment behind. Only when it is still
        // the same track: it could have run onto the next one in between.
        if let frozen = await sonos.getTrack(ip: source.ip), frozen.position == snapshot.queuePosition {
            snapshot.position = frozen.playbackPosition / 1000
        }
        guard !Task.isCancelled else { return }
        Self.log.notice("route → device: carrying \(items.count) of \(snapshot.items.count) items from \(source.nameWithCount, privacy: .public) at \(Int(snapshot.position))s")

        do {
            // Under a couple of seconds is the start of the track as far as
            // anyone can tell; the position goes in with the play so the
            // first note heard is the one the speaker stopped on.
            try await playback.play(items, from: snapshot.position > 2 ? snapshot.position : nil)
        } catch {
            Self.log.error("route → device: play failed: \(error.localizedDescription, privacy: .public)")
            if snapshot.isPlaying {
                await sonos.play(ip: source.ip)
            }
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
    }
}
