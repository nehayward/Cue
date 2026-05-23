#if targetEnvironment(macCatalyst)
import Foundation
import MusicSearchKit
import SonosKit
import UIKit

/// Glue between Clic's services and the MacGlue dock menu. Owns:
///   • dock menu state pushes  (refresh on selection / playback changes)
///   • dock command handling   (play/pause, mute, repeat, favorite, etc.)
///   • switch-speaker routing  (updates `Router.selectedID`)
///
/// One instance, installed once from ClicApp's `.onAppear`. Subsequent
/// `refresh()` calls are cheap.
@MainActor
final class DockMenuCoordinator {
    static let shared = DockMenuCoordinator()

    /// Composite identifier for `.task(id:)` in ClicApp. Reading any of these
    /// fields triggers SwiftUI observation, so a change to selection,
    /// playback state, track, or the available speaker list all re-fire the
    /// refresh task — and the previous in-flight refresh is auto-cancelled.
    struct RefreshKey: Hashable {
        let selectedGroupID: String?
        let trackUnique: String?
        let isPlaying: Bool
        let availableGroupIDs: [String]
    }

    private var dockMenu: DockMenuRenderable?
    private weak var router: Router?
    private var sonosService: SonosService?
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    private init() {}

    /// Wire the coordinator to the bundle's dock menu surface and Clic's
    /// services. Call once after MacGlue is loaded.
    func install(bridge: MacBridgeable, router: Router, sonosService: SonosService) {
        // `.onAppear` can fire more than once (window close/reopen, scene
        // changes). Installing again would re-swizzle `applicationDockMenu`
        // — leaking the previous block-backed IMP — and re-register every
        // handler, so wire up exactly once.
        guard dockMenu == nil else { return }

        self.dockMenu = bridge.dockMenu
        self.router = router
        self.sonosService = sonosService

        dockMenu?.setupDockMenu()
        dockMenu?.setDockCommandHandler { [weak self] command in
            self?.handle(command: command)
        }
        dockMenu?.setSwitchGroupHandler { [weak self] id in
            self?.router?.selectedID = id
            // Refresh straight away so the menu reflects the new speaker on
            // the next open — without waiting for the 5s background poll.
            Task { @MainActor in await self?.refresh() }
        }
        dockMenu?.setSleepTimerHandler { [weak self] minutes in
            self?.handleSleepTimer(minutes)
        }
        dockMenu?.setMenuWillOpenHandler { [weak self] in
            // Non-blocking nudge: refresh the cache when the menu opens so
            // it's current for the *next* open. The menu shown right now is
            // built synchronously from cache — kept warm by
            // `startBackgroundRefresh()` while the window is closed.
            //
            // We can't refresh synchronously here: SonosKit's
            // `getCurrentTrack` is `@MainActor`, so blocking the main thread
            // to wait for the fetch deadlocks.
            Task { @MainActor in await self?.refresh() }
        }
    }

    // MARK: - Background polling

    /// While the Mac window is closed, monitoring (`sonosPulse` / `watcher`)
    /// is cancelled for performance, so the cached model freezes. The dock
    /// menu is built synchronously from that cache — `applicationDockMenu`
    /// can't await — so we keep the cache warm with a slow poll of the
    /// selected group. Started / stopped by ClicApp on scene-phase changes.
    func startBackgroundRefresh() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopBackgroundRefresh() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Refreshes the dock-menu cache once. Driven by `.task(id:)` while the
    /// window is open, by the background poll while it's closed, and after a
    /// dock command. Cancels any in-flight refresh so the latest call wins.
    func refresh() async {
        refreshTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh()
        }
        refreshTask = task
        await task.value
    }

    private func performRefresh() async {
        guard let dockMenu, let router, let sonosService else { return }

        let id = router.selectedID
        let group = id.flatMap { id in sonosService.sorted.first(where: { $0.coordinatorID == id }) }
        let allGroups = sonosService.sorted
        let snapshot = await snapshot(for: group)
        if Task.isCancelled { return }
        push(snapshot, allGroups: allGroups, selectedID: id, to: dockMenu)
    }

    /// Forwards a snapshot + group list to the renderer. Pure plumbing.
    private func push(_ snapshot: Snapshot, allGroups: [GroupRoom], selectedID: String?, to dockMenu: DockMenuRenderable) {
        dockMenu.updateDockMenu(
            speakerName: snapshot.speakerName,
            trackTitle: snapshot.trackTitle,
            trackArtist: snapshot.trackArtist,
            isPlaying: snapshot.isPlaying,
            isRepeatAll: snapshot.isRepeatAll,
            isShuffle: snapshot.isShuffle,
            isCrossfade: snapshot.isCrossfade,
            isMuted: snapshot.isMuted,
            volume: snapshot.volume,
            favoriteSupported: snapshot.favoriteSupported,
            sleepMinutesRemaining: snapshot.sleepMinutesRemaining,
            groupIDs: allGroups.map { $0.coordinatorID },
            groupNames: allGroups.map { $0.nameWithCount },
            selectedGroupID: selectedID
        )
    }

    // MARK: - State snapshot

    private struct Snapshot {
        var speakerName: String?
        var trackTitle: String?
        var trackArtist: String?
        var isPlaying = false
        var isRepeatAll = false
        var isShuffle = false
        var isCrossfade = false
        var isMuted = false
        var volume = 0
        var favoriteSupported = false
        var sleepMinutesRemaining = 0
    }

    /// Fetches the current track + playback state from the device.
    ///
    /// Only track + playback are fetched live; the toggle states and sleep
    /// timer are read from the cached `group` model — they change rarely, and
    /// fetching them would add round-trips to every poll. Favorite state is
    /// skipped here (an internet round-trip) — the menu always shows
    /// "Favorite" and the toggle command re-checks the real state itself.
    private func snapshot(for group: GroupRoom?) async -> Snapshot {
        guard let group, let sonosService else { return Snapshot() }
        let ip = group.coordinatorRoom.ip

        let track = await sonosService.getTrack(ip: ip) ?? group.coordinatorRoom.track
        let isPlaying = (await sonosService.getPlaybackInfo(ip: ip)) == .playing
        let mode = group.playMode
        let service = track.musicService

        let sleepMinutes: Int = {
            guard let endsAt = group.coordinatorRoom.sleepTimer else { return 0 }
            return max(0, Int(endsAt.timeIntervalSinceNow / 60))
        }()

        return Snapshot(
            speakerName: group.nameWithCount,
            trackTitle: track.song,
            trackArtist: track.artist,
            isPlaying: isPlaying,
            isRepeatAll: mode.isRepeatAllEnabled,
            isShuffle: mode.isShuffleEnabled,
            isCrossfade: group.isCrossfaded ?? false,
            isMuted: group.isMuted,
            volume: Int(group.coordinatorRoom.volume.rounded()),
            favoriteSupported: !track.trackID.isEmpty && [.apple, .spotify, .soundcloud].contains(service),
            sleepMinutesRemaining: sleepMinutes
        )
    }

    // MARK: - Sleep timer

    /// Selected group, resolved from the current router state.
    private var selectedGroup: GroupRoom? {
        guard let sonosService, let id = router?.selectedID else { return nil }
        return sonosService.sorted.first { $0.coordinatorID == id }
    }

    private func handleSleepTimer(_ minutes: Int) {
        guard let sonosService, let group = selectedGroup else { return }
        Task { @MainActor in
            if minutes <= 0 {
                await sonosService.stopSleepTimer(group: group)
            } else {
                await sonosService.sleepTimer(group: group, duration: .seconds(minutes * 60))
            }
            await self.refresh()
        }
    }

    // MARK: - Command handling

    private func handle(command: DockCommand) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.execute(command: command)
            await self.refresh()
        }
    }

    private func execute(command: DockCommand) async {
        guard let sonosService, let router else { return }
        let id = router.selectedID
        let group = id.flatMap { id in sonosService.sorted.first(where: { $0.coordinatorID == id }) }

        switch command {
        case .playPause:
            guard let group else { return }
            await sonosService.togglePlayback(ip: group.coordinatorRoom.ip)

        case .next:
            guard let group else { return }
            await sonosService.next(ip: group.coordinatorRoom.ip)

        case .previous:
            guard let group else { return }
            await sonosService.previous(ip: group.coordinatorRoom.ip)

        case .volumeUp:
            guard let group else { return }
            await sonosService.setRelativeGroupVolume(ip: group.coordinatorRoom.ip, volume: 5)
            // Optimistically mirror into the cached model — monitoring is
            // paused while the window is closed, so the next snapshot would
            // otherwise show a stale level.
            group.coordinatorRoom.volume = min(100, group.coordinatorRoom.volume + 5)

        case .volumeDown:
            guard let group else { return }
            await sonosService.setRelativeGroupVolume(ip: group.coordinatorRoom.ip, volume: -5)
            group.coordinatorRoom.volume = max(0, group.coordinatorRoom.volume - 5)

        case .toggleRepeat:
            guard let group else { return }
            let mode = await sonosService.playMode(ip: group.coordinatorRoom.ip)
            let next = mode.isRepeatAllEnabled
                ? mode.subtracting(.repeatAll)
                : mode.union(.repeatAll).subtracting(.repeatOne)
            await sonosService.setPlayMode(group.coordinatorRoom.ip, mode: next)

        case .toggleShuffle:
            guard let group else { return }
            let mode = await sonosService.playMode(ip: group.coordinatorRoom.ip)
            await sonosService.setPlayMode(group.coordinatorRoom.ip, mode: mode.symmetricDifference(.shuffle))

        case .toggleCrossfade:
            guard let group else { return }
            let current = await sonosService.isCrossfaded(for: group) ?? group.isCrossfaded ?? false
            await sonosService.setCrossfade(group: group, enabled: !current)

        case .toggleMute:
            guard let group else { return }
            let current = await sonosService.isMuted(for: group) ?? group.isMuted
            await sonosService.setGroupMute(group: group, mute: !current)

        case .muteAll:
            await withTaskGroup(of: Void.self) { taskGroup in
                for group in sonosService.sorted {
                    taskGroup.addTask {
                        await sonosService.setGroupMute(group: group, mute: true)
                    }
                }
            }

        case .unmuteAll:
            await withTaskGroup(of: Void.self) { taskGroup in
                for group in sonosService.sorted {
                    taskGroup.addTask {
                        await sonosService.setGroupMute(group: group, mute: false)
                    }
                }
            }

        case .toggleFavorite:
            guard let group else { return }
            await toggleFavorite(track: group.coordinatorRoom.track)

        case .sleepAtEndOfTrack:
            guard let group else { return }
            await sonosService.sleepAtEndOfTrack(group: group)

        case .openSpeaker:
            guard let group else { return }
            router.selectedID = group.coordinatorID
            router.path.removeAll()
            // Dock-menu item clicks (unlike dock-icon clicks) don't fire
            // `applicationShouldHandleReopen`, so the Catalyst scene isn't
            // brought back when the window was closed. Request scene
            // activation explicitly so the app comes forward.
            if let session = UIApplication.shared.openSessions.first {
                UIApplication.shared.requestSceneSessionActivation(session, userActivity: nil, options: nil)
            } else {
                UIApplication.shared.requestSceneSessionActivation(nil, userActivity: nil, options: nil)
            }
        }
    }

    // MARK: - Favorite helpers

    private func isFavorite(track: SonosKit.Track) async -> Bool {
        switch track.musicService {
        case .spotify:
            return await MusicSearchService.shared.isSpotifyTrackSaved(id: track.trackID)
        case .soundcloud:
            return await MusicSearchService.shared.isSoundCloudTrackLiked(id: track.trackID) ?? false
        case .apple:
            return (try? await AppleMusicAPI.shared.isFavorite(songId: track.trackID)) ?? false
        default:
            return false
        }
    }

    private func toggleFavorite(track: SonosKit.Track) async {
        let currentlyFavorited = await isFavorite(track: track)
        let newFavorite = !currentlyFavorited
        switch track.musicService {
        case .spotify:
            if newFavorite {
                await MusicSearchService.shared.saveSpotifyTrack(id: track.trackID)
            } else {
                await MusicSearchService.shared.deleteSpotifyTrack(id: track.trackID)
            }
        case .soundcloud:
            if newFavorite {
                await MusicSearchService.shared.likeSoundCloudTrack(id: track.trackID)
            } else {
                await MusicSearchService.shared.unlikeSoundCloudTrack(id: track.trackID)
            }
        case .apple:
            try? await AppleMusicAPI.shared.updateFavoriteStatus(songId: track.trackID, favorite: newFavorite)
        default:
            break
        }
    }
}
#endif
