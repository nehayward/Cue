import DanceLogger
import Defaults
import Foundation
import SonosKit
import SwiftUI

/// Sends content where the user last chose to play, so the ordinary Play path
/// doesn't stop to ask.
///
/// The play call sites all share one shape: use the group they're already in,
/// and otherwise put up the group picker. This slots in between — the picker is
/// now the last resort rather than the default, and only appears when the
/// remembered destination genuinely can't take the content.
///
/// Nothing remembered means the device, which is what makes it the out-of-box
/// destination. `SelectGroupView` is where a different one gets chosen, and
/// playing there is what writes it back.
@MainActor
enum PlayDestinationRouter {
    /// Every Play funnels through here now, so this is the one place worth
    /// tracing when something doesn't start.
    /// `log stream --predicate 'subsystem == "dance.cue" AND category == "route"' --level debug`
    private static let log = DanceLog("route")

    /// Plays `content` at the remembered destination, falling back to the
    /// picker only when that destination genuinely can't take it.
    static func play(
        _ content: PlayableContent,
        position: QueuePosition,
        shuffle: Bool = false,
        from origin: PlayableContent? = nil,
        queue: @escaping (GroupRoom, QueuePosition) async throws -> Void
    ) async {
        await play([content], position: position, shuffle: shuffle, from: origin, queue: queue)
    }

    /// The many-at-once form, for the screens that play a whole run in one go —
    /// an artist's popular tracks, a discography. The Sonos side is the
    /// caller's closure either way, so this only really differs in what it
    /// hands the local queue and what the banner says.
    /// `shuffle` only reaches the device path — the caller's `queue` closure
    /// already sets the Sonos play mode itself.
    ///
    /// `origin` is the playlist, album or folder the Play came from, where
    /// the content itself doesn't say — a track row inside a playlist knows
    /// its parent, and the row alone doesn't. Device-side only: the speaker
    /// reads its own container off the queue it was given.
    static func play(
        _ contents: [PlayableContent],
        position: QueuePosition,
        shuffle: Bool = false,
        from origin: PlayableContent? = nil,
        queue: @escaping (GroupRoom, QueuePosition) async throws -> Void
    ) async {
        guard let first = contents.first else { return }
        // A speaker remembered from before Sonos was switched off is not a
        // destination any more.
        let destination = SonosService.shared.isEnabled ? (PlayDestination.remembered ?? .device) : .device
        log.notice("play \(String(describing: first.content.service), privacy: .public)/\(String(describing: first.content.type), privacy: .public) id=\(first.content.id, privacy: .public) count=\(contents.count) position=\(position.linkValue, privacy: .public) destination=\(String(describing: destination), privacy: .public)")

        // No network, or Offline Mode: there is no speaker to reach, so
        // this device it is — whatever the route says. The picker would
        // only offer speakers that can't answer. The remembered group is
        // left alone for when the network is back.
        if OfflineMode.shared.isActive {
            guard await playHere(contents, position: position, shuffle: shuffle, origin: origin) else {
                log.error("offline: nothing here can play \(first.content.id, privacy: .public)")
                AlertService.shared.showAlert(with: "That isn't on this device to play offline", imageName: "wifi.slash")
                return
            }
            log.notice("offline: device play started")
            return
        }

        switch destination {
        case .device:
            guard await playHere(contents, position: position, shuffle: shuffle, origin: origin) else {
                log.error("device play failed for \(first.content.id, privacy: .public)")
                askForSpeaker(contents, position: position, queue: queue)
                return
            }
            log.notice("device play started")
        case let .group(id):
            // Files play from the folder on this device; no speaker can reach
            // them. Straight to the device rather than a picker with nothing
            // in it — the remembered group is left alone for the next play.
            if contents.allSatisfy({ $0.content.service.playsOnDeviceOnly }) {
                guard await playHere(contents, position: position, shuffle: shuffle, origin: origin) else {
                    log.error("device-only content failed to play on the device")
                    AlertService.shared.showAlert(with: "Couldn't play this file on this device.", imageName: "exclamationmark.triangle")
                    return
                }
                log.notice("device-only content played on the device")
                return
            }
            guard let group = SonosService.shared.groups.first(where: { $0.coordinatorID == id }) else {
                log.error("remembered group \(id, privacy: .public) is gone")
                askForSpeaker(contents, position: position, queue: queue)
                return
            }
            // Playing on the speaker takes over from this device; adding to
            // the speaker's queue doesn't. Left running, the phone kept
            // going under a route that pointed at the speaker, with no
            // control on screen for it. Parked rather than stopped: the
            // device's queue keeps its place for the route coming back.
            if [.now, .replace].contains(position) {
                LocalPlaybackService.shared.park()
            }
            do {
                try await queue(group, position)
                log.notice("queued to \(group.nameWithCount, privacy: .public)")
            } catch {
                log.error("queue failed: \(error.localizedDescription, privacy: .public)")
                AlertService.shared.showAlert(with: error.localizedDescription, imageName: "exclamationmark.triangle")
            }
        }
    }

    /// Artist or song radio at the remembered destination.
    ///
    /// A speaker plays Sonos' own radio for the service (`onGroup`). This
    /// device plays Apple Music's station for the artist or song, which
    /// MusicKit runs itself. Apple is the only service with stations the
    /// device can play, so anything else still goes to a speaker, through
    /// the picker when none is remembered.
    static func playRadio(from seed: PlayableContent, onGroup: @escaping (GroupRoom) async throws -> Void) async {
        if !OfflineMode.shared.isActive, let group = rememberedGroup {
            do {
                try await onGroup(group)
            } catch {
                log.error("speaker radio failed: \(error.localizedDescription, privacy: .public)")
                AlertService.shared.showAlert(with: error.localizedDescription, imageName: "exclamationmark.triangle")
            }
            return
        }
        guard let station = await MusicSearchService.shared.appleStation(for: seed) else {
            log.notice("no Apple station for \(seed.content.id, privacy: .public)")
            askForSpeaker([seed], position: .now) { group, _ in try await onGroup(group) }
            return
        }
        await play(station, position: .now, from: seed) { group, _ in try await onGroup(group) }
    }

    /// The remembered group, for the Sonos-only actions — song and artist
    /// radio, grouping — that have no local equivalent to fall back on. `nil` means the caller
    /// still has to ask.
    static var rememberedGroup: GroupRoom? {
        guard SonosService.shared.isEnabled else { return nil }
        guard let id = PlayDestination.remembered?.groupID else { return nil }
        return SonosService.shared.groups.first { $0.coordinatorID == id }
    }

    /// The remembered destination can't take this — artists, Spotify, and a
    /// station from a service the device can't stream have no local backend,
    /// and a remembered group can simply be gone. Falling
    /// back to the picker keeps those playable; an alert on its own was a dead
    /// end, since the route button is the only other way to change destination.
    /// Playing from the picker writes the new destination, so the next Play
    /// goes straight there.
    private static func askForSpeaker(
        _ contents: [PlayableContent],
        position: QueuePosition,
        queue: @escaping (GroupRoom, QueuePosition) async throws -> Void
    ) {
        // With Sonos switched off there is no speaker to offer, and a picker
        // with nothing in it is a dead end. Say so instead.
        guard SonosService.shared.isEnabled else {
            log.notice("no destination can take this — Sonos is off")
            AlertService.shared.showAlert(with: "This can't play on this device", imageName: "exclamationmark.triangle")
            return
        }
        log.notice("no destination can take this — asking")
        Router.main.sheet(to: .selectGroup(
            selectedGroupService: SelectedGroupService.shared,
            onQueueSelection: queue,
            defaultPosition: position,
            content: contents.first
        ))
    }

    private static func playHere(_ contents: [PlayableContent], position: QueuePosition, shuffle: Bool, origin: PlayableContent?) async -> Bool {
        // Artists and Spotify have no local backend at all, so don't even
        // try — falling straight through to the picker is the useful answer.
        // TuneIn and Apple Music stations do play here; other stations don't.
        guard contents.contains(where: { LocalPlaybackService.shared.canPlayAnywhereLocally($0) }) else {
            log.notice("no local backend for this content")
            return false
        }
        do {
            // A song tapped in an album or playlist plays the list from that
            // song, not the song alone — what a speaker does with the same
            // tap, since the queue closure hands it the parent.
            if let origin, contents.count == 1, !shuffle, [.now, .replace].contains(position),
               origin.content.type == .album || origin.content.type == .libraryAlbum || origin.content.type.isPlaylist,
               try await LocalPlaybackService.shared.play(contents[0], in: origin) {
                record(contents)
                announce(contents, position: position)
                return true
            }
            try await LocalPlaybackService.shared.enqueue(contents, at: position, shuffle: shuffle, from: origin)
            record(contents)
            announce(contents, position: position)
            return true
        } catch {
            // A container that resolved to nothing, or Apple playback without a
            // subscription.
            log.error("enqueue threw: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Adds the play to history. The Sonos path gets this from
    /// `QueueManager.addToQueue`, which the device path never goes through — so
    /// until this existed, playing on This Device left no trace in Recently
    /// Played at all.
    ///
    /// Records the leading item rather than every track, matching both the
    /// Sonos side (which records the one thing that was queued, album or
    /// playlist included) and the banner below: a run of an artist's tracks is
    /// one action, and logging twenty rows would bury everything else.
    private static func record(_ contents: [PlayableContent]) {
        guard let first = contents.first else { return }
        withAnimation {
            PlayHistoryService.shared.history.remove(first)
            PlayHistoryService.shared.history.insert(first, at: 0)
        }
    }

    /// One item gets the artwork banner it always got; a run of them gets a
    /// count instead, since there's no single piece of art that stands for it.
    private static func announce(_ contents: [PlayableContent], position: QueuePosition) {
        guard contents.count > 1 else {
            AlertService.shared.showAlertContent(
                with: contents[0],
                subtitle: subtitle(for: position),
                symbolName: "iphone.radiowaves.left.and.right"
            )
            return
        }
        AlertService.shared.showAlert(
            with: "\(contents.count) items — \(deviceSubtitle(for: position))",
            imageName: "iphone.radiowaves.left.and.right"
        )
    }

    private static func subtitle(for position: QueuePosition) -> LocalizedStringKey {
        switch position {
        case .next, .front: "Playing next on this device"
        case .end: "Added to device queue"
        case .now, .replace: "Playing on this device"
        }
    }

    /// The same wording as `subtitle(for:)`, as a plain string — the count
    /// banner interpolates rather than taking a key.
    private static func deviceSubtitle(for position: QueuePosition) -> String {
        switch position {
        case .next, .front: "playing next on this device"
        case .end: "added to device queue"
        case .now, .replace: "playing on this device"
        }
    }
}
