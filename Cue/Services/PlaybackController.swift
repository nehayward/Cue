import Defaults
import Foundation
import SonosKit
import UIKit

/// What the player draws and what its controls do, for whichever backend is
/// on the other end: this device (`LocalPlaybackService`) or one Sonos group
/// (`SonosGroupController`).
///
/// The player used to be two players in one screen — a tree of `Local…`
/// views reading `LocalPlaybackService` and a tree of `Group…` views reading
/// the speaker — and a route switch tore one down and built the other. Now
/// there is one tree, and a switch only changes which controller it reads:
/// the title, the scrubber and the transport stay where they are and carry
/// on with what's playing. `PlaybackRoute.presented` is the controller on
/// screen; it holds on the source while a hand-off is carrying the queue
/// across, so the song never drops out from under the player mid-switch.
///
/// Times are in seconds on both sides — the speaker's milliseconds are
/// converted here, not in the views. Speaker-only extras (grouping, TV mode,
/// EQ, room volume) aren't part of it; they stay behind `group`.
@MainActor
protocol PlaybackController: AnyObject {
    /// Where this controller plays.
    var destination: PlayDestination { get }
    /// The speaker group, for the extras only a speaker has. Nil for this
    /// device.
    var group: GroupRoom? { get }
    /// What to call it: the device's name, or the group's.
    var name: String { get }

    // MARK: Now playing

    /// The item the player draws: the song on air while a station plays.
    /// Nil with nothing loaded.
    var nowPlayingDisplay: PlayableContent? { get }
    /// Something is loaded to play — the controls have something to act on.
    var isActive: Bool { get }
    var isPlaying: Bool { get }
    /// Playing has been asked for and hasn't started yet: a load, a buffer,
    /// a speaker in TRANSITIONING.
    var isLoading: Bool { get }
    /// Seconds; zero for a live stream, which hides the scrubber.
    var duration: TimeInterval { get }
    /// Whether the position is moving, which is when a bar runs.
    var isClockRunning: Bool { get }
    /// Seconds into the song at `date`, on the running clock (see
    /// `Docs/PlaybackProgress.md`).
    func position(at date: Date) -> TimeInterval
    var audioQuality: SonosTrackQuality? { get }

    // MARK: Transport

    /// Whether there is a Previous button at all. A live station has none.
    var showsPrevious: Bool { get }
    var canGoBack: Bool { get }
    /// Whether there is a Next button at all.
    var showsNext: Bool { get }
    var hasNext: Bool { get }
    var canScrub: Bool { get }

    func togglePlayback() async
    func next() async
    func previous() async
    func seek(to seconds: TimeInterval) async
    /// A finger went down on the scrubber: reports stop moving the position
    /// until `endScrubbing(at:)`.
    func beginScrubbing()
    /// The finger came up, at `seconds`; nil seeks nowhere — a drag called
    /// off because the source changed under it.
    func endScrubbing(at seconds: TimeInterval?) async

    // MARK: Play mode

    var isShuffled: Bool { get }
    var repeatMode: LocalPlaybackService.RepeatMode { get }
    func setShuffle(_ on: Bool) async
    func setRepeatMode(_ mode: LocalPlaybackService.RepeatMode) async

    // MARK: Queue

    /// The current song's 1-based place in the queue; zero when it isn't
    /// playing from one.
    var queuePosition: Int { get }
    var queueCount: Int { get }

    // MARK: Sleep timer

    var sleepTimerEndDate: Date? { get }
    var sleepsAtEndOfTrack: Bool { get }
    func cancelSleepTimer() async
}

extension PlaybackController {
    func position() -> TimeInterval {
        position(at: .now)
    }
}

// MARK: - This device

/// Most of the protocol is the service's own API already; this is the rest.
extension LocalPlaybackService: PlaybackController {
    var destination: PlayDestination { .device }
    var group: GroupRoom? { nil }
    var name: String { UIDevice.current.name }

    var isClockRunning: Bool { isPlaying }

    func position(at date: Date) -> TimeInterval {
        estimatedProgress(at: date)
    }

    var showsPrevious: Bool { !isPlayingStation }
    var canGoBack: Bool { true }
    /// An Apple Music station is a stream of songs, so it keeps Next.
    var showsNext: Bool { !isPlayingStation || isPlayingAppleStation }
    var canScrub: Bool { !isPlayingStation }

    func beginScrubbing() {}

    func endScrubbing(at seconds: TimeInterval?) async {
        guard let seconds else { return }
        seek(to: seconds)
    }

    var queuePosition: Int { queue.isEmpty ? 0 : currentIndex + 1 }
    var queueCount: Int { queue.count }
}

// MARK: - A speaker

/// One Sonos group behind `PlaybackController`.
///
/// Holds the coordinator's id, not the `GroupRoom`: a topology refresh
/// replaces every group instance, so the group is looked up on each read —
/// the same rule `PlaybackRoute.group` follows. That also makes it free to
/// make one per read; it keeps no state of its own, and everything it reads
/// is `@Observable` underneath.
@MainActor
final class SonosGroupController: PlaybackController {
    let coordinatorID: String

    init(coordinatorID: String) {
        self.coordinatorID = coordinatorID
    }

    private var sonos: SonosService { .shared }

    var group: GroupRoom? {
        sonos.groups.first { $0.coordinatorID == coordinatorID }
    }

    private var room: Room? { group?.coordinatorRoom }

    /// The speaker's current track, when it reports one.
    private var track: Track? {
        guard let track = room?.track, !track.isEmpty else { return nil }
        return track
    }

    var destination: PlayDestination { .group(coordinatorID) }
    var name: String { group?.nameWithCount ?? "Speaker" }

    var nowPlayingDisplay: PlayableContent? { track?.toPlayable }
    /// Always, for a speaker that's there: Play goes to it whatever it
    /// reports — a paused line-in can have no track at all.
    var isActive: Bool { group != nil }
    var isPlaying: Bool { room?.isPlaying ?? false }
    var isLoading: Bool { room?.isTransitioning ?? false }
    var duration: TimeInterval { (room?.track.duration ?? 0) / 1000 }
    var isClockRunning: Bool { room?.isClockRunning ?? false }

    func position(at date: Date) -> TimeInterval {
        (room?.estimatedPlaybackPosition(at: date) ?? 0) / 1000
    }

    var audioQuality: SonosTrackQuality? { group?.audioQuality }

    var showsPrevious: Bool { true }
    var canGoBack: Bool {
        guard let group else { return false }
        return group.availableActions.contains(.previous) || group.playbackService == .queue
    }
    var showsNext: Bool { true }
    var hasNext: Bool { group?.availableActions.contains(.next) ?? false }
    var canScrub: Bool { group?.availableActions.contains(.scrubbable) ?? false }

    func togglePlayback() async {
        guard let group else { return }
        await sonos.togglePlayPause(for: group)
    }

    /// Instant and coalesced: the new song shows at once, and the speaker's
    /// socket confirms it (`SonosService+TrackSkip.swift`).
    func next() async {
        guard let room else { return }
        await sonos.next(ip: room.ip)
    }

    func previous() async {
        guard let room else { return }
        await sonos.previous(ip: room.ip)
    }

    func seek(to seconds: TimeInterval) async {
        guard let group else { return }
        await sonos.seek(to: seconds * 1000, on: group)
    }

    func beginScrubbing() {
        // Keeps polls and socket events off the position while the finger
        // is down.
        group?.isEditingPlayback = true
    }

    func endScrubbing(at seconds: TimeInterval?) async {
        guard let group else { return }
        // Same turn as the seek starts, so no report lands in between: from
        // here `beginSeek` decides which reports count.
        group.isEditingPlayback = false
        guard let seconds else { return }
        await sonos.seek(to: seconds * 1000, on: group)
    }

    var isShuffled: Bool { group?.playMode.isShuffleEnabled ?? false }

    var repeatMode: LocalPlaybackService.RepeatMode {
        guard let mode = group?.playMode else { return .off }
        if mode.isRepeatOneEnabled { return .one }
        if mode.isRepeatAllEnabled { return .all }
        return .off
    }

    func setShuffle(_ on: Bool) async {
        guard let group else { return }
        var mode = group.playMode
        if on { mode.insert(.shuffle) } else { mode.remove(.shuffle) }
        await setPlayMode(mode, on: group)
    }

    func setRepeatMode(_ repeatMode: LocalPlaybackService.RepeatMode) async {
        guard let group else { return }
        var mode = group.playMode
        mode.remove(.repeatAll)
        mode.remove(.repeatOne)
        switch repeatMode {
        case .off: break
        case .all: mode.insert(.repeatAll)
        case .one: mode.insert(.repeatOne)
        }
        await setPlayMode(mode, on: group)
    }

    /// Optimistic, as the queue panel's buttons are: the speaker confirms on
    /// its next report.
    private func setPlayMode(_ mode: PlayMode, on group: GroupRoom) async {
        group.playMode = mode
        await sonos.setPlayMode(group.ip, mode: mode)
    }

    var queuePosition: Int {
        guard let group, group.playbackService == .queue else { return 0 }
        return group.coordinatorRoom.track.position
    }

    var queueCount: Int { room?.queueTotal ?? 0 }

    var sleepTimerEndDate: Date? { room?.sleepTimer }
    var sleepsAtEndOfTrack: Bool { false }

    func cancelSleepTimer() async {
        guard let group else { return }
        await sonos.stopSleepTimer(group: group)
    }
}

// MARK: - Held through a hand-off

/// The source while a hand-off holds the player on it (`PlaybackRoute.hold`):
/// the song it was playing and everything about it, with the hold's word on
/// playing and position — the source is paused on its way out, and the
/// target picks the song up where the hold's clock says — and nothing to
/// press. A command now would only race the hand-off: the source is coming
/// down and the target isn't up.
///
/// So the views draw a hand-off without knowing about one: the transport
/// greys out, the play button pulses, and the bars run on.
@MainActor
final class HeldPlaybackController: PlaybackController {
    let source: any PlaybackController
    let hold: PlaybackRoute.Hold

    init(source: any PlaybackController, hold: PlaybackRoute.Hold) {
        self.source = source
        self.hold = hold
    }

    var destination: PlayDestination { source.destination }
    var group: GroupRoom? { source.group }
    var name: String { source.name }

    var nowPlayingDisplay: PlayableContent? { source.nowPlayingDisplay }
    /// Nothing to act on until the hand-off lands.
    var isActive: Bool { false }
    var isPlaying: Bool { hold.wasPlaying }
    var isLoading: Bool { true }
    var duration: TimeInterval { source.duration }
    var isClockRunning: Bool { hold.isClockRunning }

    func position(at date: Date) -> TimeInterval {
        hold.position(at: date)
    }

    var audioQuality: SonosTrackQuality? { source.audioQuality }

    var showsPrevious: Bool { source.showsPrevious }
    var canGoBack: Bool { false }
    var showsNext: Bool { source.showsNext }
    var hasNext: Bool { false }
    var canScrub: Bool { false }

    func togglePlayback() async {}
    func next() async {}
    func previous() async {}
    func seek(to seconds: TimeInterval) async {}
    func beginScrubbing() {}
    func endScrubbing(at seconds: TimeInterval?) async {}

    var isShuffled: Bool { source.isShuffled }
    var repeatMode: LocalPlaybackService.RepeatMode { source.repeatMode }
    func setShuffle(_ on: Bool) async {}
    func setRepeatMode(_ mode: LocalPlaybackService.RepeatMode) async {}

    var queuePosition: Int { source.queuePosition }
    var queueCount: Int { source.queueCount }

    var sleepTimerEndDate: Date? { source.sleepTimerEndDate }
    var sleepsAtEndOfTrack: Bool { source.sleepsAtEndOfTrack }

    /// A sleep timer is the source's own, and calling it off doesn't touch
    /// the hand-off.
    func cancelSleepTimer() async {
        await source.cancelSleepTimer()
    }
}
