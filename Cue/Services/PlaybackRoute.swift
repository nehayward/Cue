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

    /// True while a hand-off is in flight. The accessory shows it, and a
    /// second tap on the route button is ignored until it clears.
    private(set) var isSwitching = false

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
    /// Nothing playing at the source means there is nothing to carry: the
    /// destination is remembered and the next Play goes there, which is all
    /// the route button used to do.
    func switchTo(_ target: PlayDestination) async {
        guard !isSwitching, target != destination else { return }
        isSwitching = true
        defer { isSwitching = false }

        let source = group
        switch target {
        case .device:
            remember(.device)
            await handOffToDevice(from: source)
        case let .group(id):
            guard let group = SonosService.shared.groups.first(where: { $0.coordinatorID == id }) else {
                Self.log.error("route → \(id, privacy: .public): group is gone")
                AlertService.shared.showAlert(with: "That speaker isn't available right now", imageName: "hifispeaker.slash")
                return
            }
            remember(.group(id))
            await handOffToGroup(group, from: source)
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
    }

    private func localSnapshot() -> Snapshot? {
        let playback = LocalPlaybackService.shared
        guard playback.isActive, let current = playback.nowPlaying else { return nil }
        return Snapshot(items: [current] + playback.upNext, position: playback.progress, isPlaying: playback.isPlaying)
    }

    /// Only a queue can be carried across — radio, TV and a line-in have
    /// nothing to hand over, so those come back `nil` and the speaker keeps
    /// going.
    private func snapshot(of group: GroupRoom) async -> Snapshot? {
        let sonos = SonosService.shared
        let track = group.coordinatorRoom.track
        guard !track.isEmpty else { return nil }
        // Fetched rather than trusting the cached value: after backgrounding
        // it can lag the device, the same reason `seek(trackNumber:)` does.
        let service = await sonos.playbackService(ip: group.ip) ?? group.playbackService
        guard service == .queue else { return nil }
        let queue = await sonos.getQueue(ip: group.ip)
        guard !queue.isEmpty else { return nil }
        // Queue positions are 1-based; the current one is on the track.
        let start = queue.firstIndex { $0.metadata?.position == track.position }
            ?? max(0, min(track.position - 1, queue.count - 1))
        return Snapshot(
            items: Array(queue[start...]),
            // `Room.playbackPosition` is in milliseconds.
            position: group.coordinatorRoom.playbackPosition / 1000,
            isPlaying: group.coordinatorRoom.isPlaying
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

        do {
            // The first track alone, so it starts now; the rest fill in
            // behind it while it plays. One call for the lot meant the first
            // note waited on every AddURIToQueue round trip.
            try await sonos.queue(contents: [first], group: target, position: .replace, startIndex: 0)
        } catch {
            Self.log.error("route → \(target.nameWithCount, privacy: .public): replace failed: \(error.localizedDescription, privacy: .public)")
            if fromDevice {
                await restoreLocal(snapshot)
            }
            AlertService.shared.showAlert(with: "Couldn't move playback to \(target.nameWithCount)", imageName: "exclamationmark.triangle")
            return
        }

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

        let rest = Array(items.dropFirst())
        guard !rest.isEmpty else { return }
        do {
            try await sonos.queue(contents: rest, group: target, position: .end)
        } catch {
            // Playing already; the tail is what's missing.
            Self.log.error("route → \(target.nameWithCount, privacy: .public): tail failed: \(error.localizedDescription, privacy: .public)")
            AlertService.shared.showAlert(with: "Some of the queue couldn't be added on \(target.nameWithCount)", imageName: "exclamationmark.triangle")
        }
    }

    private func restoreLocal(_ snapshot: Snapshot) async {
        let playback = LocalPlaybackService.shared
        do {
            try await playback.play(snapshot.items)
            if snapshot.position > 2 {
                playback.seek(to: snapshot.position)
            }
            if !snapshot.isPlaying {
                playback.pause()
            }
        } catch {
            Self.log.error("restore on device failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - To this device

    private func handOffToDevice(from source: GroupRoom?) async {
        guard let source else { return }
        guard let snapshot = await snapshot(of: source) else {
            Self.log.notice("route → device: nothing on \(source.nameWithCount, privacy: .public) to carry over")
            return
        }

        let playback = LocalPlaybackService.shared
        let items = snapshot.items.filter { playback.canPlayLocally($0) }
        guard let first = items.first else {
            Self.log.notice("route → device: nothing on \(source.nameWithCount, privacy: .public) has a local backend")
            AlertService.shared.showAlert(with: "Nothing playing on \(source.nameWithCount) can play on this device", imageName: "iphone.slash")
            return
        }
        Self.log.notice("route → device: carrying \(items.count) of \(snapshot.items.count) items from \(source.nameWithCount, privacy: .public) at \(Int(snapshot.position))s")

        // Speaker down first, so the two don't overlap; resumed below if the
        // device can't take over.
        let sonos = SonosService.shared
        if snapshot.isPlaying {
            await sonos.pause(ip: source.ip)
        }

        do {
            try await playback.play(items)
        } catch {
            Self.log.error("route → device: play failed: \(error.localizedDescription, privacy: .public)")
            if snapshot.isPlaying {
                await sonos.play(ip: source.ip)
            }
            AlertService.shared.showAlert(with: error.localizedDescription, imageName: "exclamationmark.triangle")
            return
        }
        if snapshot.position > 2 {
            playback.seek(to: snapshot.position)
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
