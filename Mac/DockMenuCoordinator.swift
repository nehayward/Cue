#if targetEnvironment(macCatalyst)
import Defaults
import Foundation
import Observation
import SonosKit
import UIKit

/// Glue between Cue's player and the MacGlue dock menu, whose right-click
/// menu controls whatever the player shows (`PlaybackRoute.presented`): this
/// Mac or a Sonos group, as the mini player and the player do.
///
///   • the menu's state, built from the player and pushed to the bundle
///     whenever what it reads changes (`withObservationTracking`), since the
///     swizzled `applicationDockMenu(_:)` builds the menu synchronously and
///     can't wait for anything
///   • its commands: transport (a book's ±15/30 s), play mode, the sleep
///     timer, a group's volume and mutes, Favorite
///   • its route list: This Mac and each Sonos group, switched as Play On
///     switches, the free tier's locks included
///
/// One instance, installed once from CueApp's `.onAppear`.
@MainActor
final class DockMenuCoordinator {
    static let shared = DockMenuCoordinator()

    private var dockMenu: DockMenuRenderable?
    /// The state last pushed, so an unchanged one isn't sent again.
    private var lastState: DockMenuState?
    /// The coalesced rebuild after a change, while one is waiting.
    private var pendingRefresh: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    /// The group whose crossfade was last asked for.
    private var crossfadeAsked: ObjectIdentifier?
    private let encoder = JSONEncoder()

    private var route: PlaybackRoute { .shared }
    private var sonos: SonosService { .shared }
    private var books: AudiobookPlayer { .shared }

    private init() {}

    /// Wires the dock menu to the player, once: `.onAppear` fires again as
    /// windows close and open, and installing again would swizzle
    /// `applicationDockMenu` again and leak the block before it. Nothing
    /// without the MacGlue bundle.
    func installIfNeeded() {
        guard dockMenu == nil, let dockMenu = MenuAppLaunchAtLoginManager.shared.bridge?.dockMenu else { return }
        self.dockMenu = dockMenu

        dockMenu.setupDockMenu()
        dockMenu.setDockCommandHandler { [weak self] command in
            Task { @MainActor [weak self] in
                await self?.execute(command)
            }
        }
        dockMenu.setSwitchRouteHandler { [weak self] id in
            Task { @MainActor [weak self] in
                self?.switchRoute(to: id)
            }
        }
        dockMenu.setSleepTimerHandler { [weak self] minutes in
            Task { @MainActor [weak self] in
                await self?.setSleepTimer(minutes: minutes)
            }
        }
        dockMenu.setMenuWillOpenHandler { [weak self] in
            // The menu showing now is drawn from the cache; this only reads
            // what nothing follows live, for the next open.
            Task { @MainActor [weak self] in
                await self?.readOnOpen()
            }
        }
        observe()
    }

    // MARK: - Keeping the menu current

    /// Builds the state, pushes it if it changed, and watches everything it
    /// read: any change rebuilds it, a quarter second later so a burst (a
    /// new song lands as several writes) is one rebuild.
    private func observe() {
        let state = withObservationTracking {
            makeState()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }
        push(state)
        readCrossfadeIfUnknown()
    }

    /// A group's crossfade is known only once something has asked (the
    /// player does as it opens), and the menu would show it off until then.
    /// Asked once a group: a topology refresh makes new groups, which ask
    /// again.
    private func readCrossfadeIfUnknown() {
        guard let group = route.presented.group, !route.isHolding, group.isCrossfaded == nil,
              crossfadeAsked != ObjectIdentifier(group) else { return }
        crossfadeAsked = ObjectIdentifier(group)
        Task {
            if let crossfaded = await sonos.isCrossfaded(for: group), group.isCrossfaded == nil {
                group.isCrossfaded = crossfaded
            }
        }
    }

    private func scheduleRefresh() {
        guard pendingRefresh == nil else { return }
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self else { return }
            pendingRefresh = nil
            observe()
        }
    }

    private func push(_ state: DockMenuState) {
        guard state != lastState, let dockMenu, let data = try? encoder.encode(state) else { return }
        lastState = state
        dockMenu.updateDockMenu(data)
    }

    /// Kept for `CueApp.handleScenePhase`. While Cue is off screen with
    /// Sonos monitoring stopped, nothing writes a speaker's state into the
    /// model the menu follows, so a slow read of the group being heard keeps
    /// it current. It does nothing while monitoring runs, or on this Mac.
    func startBackgroundRefresh() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshSpeakerIfUnmonitored()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func stopBackgroundRefresh() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func refreshSpeakerIfUnmonitored() async {
        guard !sonos.allowsMonitoring, let group = route.audibleGroup else { return }
        try? await sonos.updateGroups(from: [group])
    }

    /// As the menu opens: what the monitor doesn't read (a timer set or
    /// called off from elsewhere, whether the song is a favorite), read now
    /// so the next open has it, as the player reads them as it opens. The
    /// model's observers rebuild the menu.
    private func readOnOpen() async {
        await refreshSpeakerIfUnmonitored()
        if let group = route.presented.group, !route.isHolding {
            await sonos.getSleepTimer(group: group)
        }
        if let target = favoriteTarget(), LiveActivityFavoriteStore.shared.favorites[target.trackID] == nil {
            // Records what it reads in the store the menu draws from.
            _ = await MusicSearchService.shared.isFavorite(trackID: target.trackID, service: target.service)
        }
    }

    // MARK: - The state

    /// A book's file is a chapter or more, so a book skips 15 and 30 s where
    /// a song goes to the previous and the next (`PlayerCommands`).
    private var isBook: Bool { PlayerCommands.isBook }

    private func makeState() -> DockMenuState {
        let controller = route.presented
        let item = controller.nowPlayingDisplay
        let isBook = isBook
        var state = DockMenuState()

        state.routes = routes()

        // Sleep timer, on whichever route; End of Chapter for a book.
        state.canSetSleepTimer = controller.isActive && item != nil
        state.sleepEndsAt = controller.sleepTimerEndDate
        state.endOfItemTitle = isBook ? "End of Chapter" : "End of Song"
        state.canSleepAtEndOfItem = isBook || controller.duration > 0
        state.sleepsAtEndOfItem = isBook ? books.sleepsAt != nil : controller.sleepsAtEndOfTrack

        // Playback. A book has no shuffle or repeat, as in the player.
        if item != nil, !isBook {
            let repeatMode: DockMenuState.RepeatMode = switch controller.repeatMode {
            case .off: .off
            case .all: .all
            case .one: .one
            }
            state.repeatMode = repeatMode
            state.isShuffled = controller.isShuffled
            state.canChangePlayMode = controller.isActive
            // As the player's menu: nothing to shuffle with one song left.
            state.canShuffle = controller.isActive
                && (controller.group != nil || controller.isShuffled || LocalPlaybackService.shared.upNextCount >= 2)
        }
        if let group = controller.group, !route.isHolding {
            state.isCrossfaded = group.isCrossfaded ?? false
        }

        // Volume: the group being heard, as the hardware buttons have it.
        // Nothing on this Mac, whose volume is macOS's.
        if let group = route.audibleGroup {
            state.volume = Int(group.groupVolume.rounded())
            state.isVolumeFixed = group.coordinatorRoom.isOutputFixed
            state.isMuted = group.isMuted
            state.showsMuteAll = FeatureGate.shared.isAvailable(.allRooms) && activeGroups.count > 1
        }

        // Now Playing.
        if isBook, let book = books.current {
            state.nowPlaying = Self.line(book.book.title, books.currentChapter?.title ?? book.book.subtitle)
        } else if let item {
            // The artist alone where it's known: a speaker's subtitle is
            // "Artist • Album".
            let artist = item.metadata?.artist.flatMap { $0.isEmpty ? nil : $0 }
            state.nowPlaying = Self.line(item.title, artist ?? item.subtitle)
        }
        if route.isHolding {
            state.nowPlayingNote = "Moving to \(route.group?.nameWithCount ?? "This Mac")…"
        }
        if let target = favoriteTarget() {
            state.showsFavorite = true
            state.isFavorite = LiveActivityFavoriteStore.shared.favorites[target.trackID] ?? false
        }

        // Transport.
        state.isPlaying = controller.isPlaying
        state.canPlay = controller.isActive
        if isBook {
            state.previousTitle = "Back \(Int(AudiobookPlayer.skipBackInterval)) Seconds"
            state.canGoBack = true
            state.nextTitle = "Forward \(Int(AudiobookPlayer.skipForwardInterval)) Seconds"
            state.hasNext = true
        } else {
            // A live station has nothing to go back or on to.
            state.previousTitle = controller.showsPrevious ? "Previous" : nil
            state.canGoBack = controller.canGoBack && item != nil
            state.nextTitle = controller.showsNext ? "Next" : nil
            state.hasNext = controller.hasNext
        }
        return state
    }

    /// The Sonos groups that can play, by name as Play On lists its rooms
    /// (the service's own sort can put whatever plays first).
    private var activeGroups: [GroupRoom] {
        sonos.groups
            .filter(\.isActive)
            .sorted { $0.coordinatorRoom.name.localizedStandardCompare($1.coordinatorRoom.name) == .orderedAscending }
    }

    /// This Mac and each group, the route checked. None while no speaker
    /// can be reached (Sonos off, no Wi‑Fi) or none is found: This Mac on
    /// its own would be a list of one.
    private func routes() -> [DockMenuState.Route] {
        guard sonos.isAvailable else { return [] }
        let groups = activeGroups
        guard !groups.isEmpty else { return [] }
        let gate = FeatureGate.shared
        let destination = route.destination
        let device = DockMenuState.Route(
            id: DockMenuState.deviceRouteID,
            name: "This Mac",
            isCurrent: destination == .device,
            isLocked: gate.needsSuper(.onDevicePlayback)
        )
        return [device] + groups.map { group in
            DockMenuState.Route(
                id: group.coordinatorID,
                name: group.nameWithCount,
                isCurrent: destination.groupID == group.coordinatorID,
                isLocked: !gate.isGroupUnlocked(group.coordinatorID)
            )
        }
    }

    /// "Title — Artist", either alone when the other is empty.
    private static func line(_ title: String, _ detail: String) -> String? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (title.isEmpty, detail.isEmpty) {
        case (true, true): return nil
        case (false, true): return title
        case (true, false): return detail
        case (false, false): return "\(title) — \(detail)"
        }
    }

    /// The song Favorite likes, as the player's like button has it: a
    /// speaker's track, or this Mac's song (the one on air, for a station
    /// Apple Music knows). Nil where its service can't like it, for a book,
    /// and through a hand-off.
    private func favoriteTarget() -> (trackID: String, service: MusicService)? {
        guard !route.isHolding, !isBook else { return nil }
        let controller = route.presented
        if let group = controller.group {
            let track = group.coordinatorRoom.track
            guard !track.trackID.isEmpty, track.musicService.supportsFavoriteTrack else { return nil }
            return (track.trackID, track.musicService)
        }
        let local = LocalPlaybackService.shared
        if let song = local.onAirMatch {
            return (song.id, song.content.service)
        }
        guard let item = local.nowPlaying, !item.content.type.isRadio,
              item.content.service.supportsFavoriteTrack else { return nil }
        return (item.id, item.content.service)
    }

    // MARK: - Commands

    private func execute(_ command: DockCommand) async {
        let controller = route.presented
        switch command {
        case .playPause:
            await PlayerCommands.togglePlayback()
        case .next:
            await PlayerCommands.next()
        case .previous:
            await PlayerCommands.previous()

        case .volumeUp:
            await PlayerCommands.nudgeSpeakerVolume(by: 1)
        case .volumeDown:
            await PlayerCommands.nudgeSpeakerVolume(by: -1)
        case .volumeUpLarge:
            await PlayerCommands.nudgeSpeakerVolume(by: 5)
        case .volumeDownLarge:
            await PlayerCommands.nudgeSpeakerVolume(by: -5)

        case .cycleRepeat:
            await PlayerCommands.cycleRepeat()

        case .toggleShuffle:
            await PlayerCommands.toggleShuffle()

        case .toggleCrossfade:
            guard let group = controller.group else { return }
            let current: Bool
            if let known = group.isCrossfaded {
                current = known
            } else {
                current = await sonos.isCrossfaded(for: group) ?? false
            }
            await sonos.setCrossfade(group: group, enabled: !current)

        case .toggleMute:
            guard let group = route.audibleGroup else { return }
            await PlayerCommands.setMuted(!group.isMuted, group)

        case .muteAll, .unmuteAll:
            let mute = command == .muteAll
            let groups = activeGroups.filter { FeatureGate.shared.isGroupUnlocked($0.coordinatorID) }
            await withDiscardingTaskGroup { tasks in
                for group in groups {
                    tasks.addTask { @MainActor in
                        await PlayerCommands.setMuted(mute, group)
                    }
                }
            }

        case .toggleFavorite:
            await toggleFavorite()

        case .openPlayer:
            bringCueForward()
            Router.main.isPlayerPresented = true

        case .sleepAtEndOfItem:
            await sleepAtEndOfItem()
        }
    }

    // MARK: Volume

    // MARK: Favorite

    /// The like button's tap: the store first, so the next open shows it,
    /// and Plex's and Subsonic's rating caches in step for their rows.
    private func toggleFavorite() async {
        guard let target = favoriteTarget() else { return }
        let store = LiveActivityFavoriteStore.shared
        let current: Bool
        if let known = store.favorites[target.trackID] {
            current = known
        } else {
            current = await MusicSearchService.shared.isFavorite(trackID: target.trackID, service: target.service)
        }
        let favorite = !current
        store.set(favorite, for: target.trackID)
        switch target.service {
        case .plex: FavoriteRatingCache.shared.set(favorite ? 10 : 0, for: target.trackID)
        case .subsonic: FavoriteRatingCache.shared.set(favorite ? 1 : 0, for: target.trackID)
        default: break
        }
        await MusicSearchService.shared.setFavorite(favorite, trackID: target.trackID, service: target.service)
    }

    // MARK: Sleep timer

    /// As the player's menu sets one, on whichever route: on the speaker for
    /// a group, else on this Mac. Any of these puts End of Chapter away, or
    /// it would move the new timer back to the chapter's end.
    private func setSleepTimer(minutes: Int) async {
        guard !route.isHolding else { return }
        let controller = route.presented
        books.forgetChapterSleep()
        guard minutes > 0 else {
            await controller.cancelSleepTimer()
            return
        }
        let duration = Duration.seconds(minutes * 60)
        if let group = controller.group {
            await sonos.sleepTimer(group: group, duration: duration)
        } else {
            LocalPlaybackService.shared.sleepTimer(duration)
        }
    }

    private func sleepAtEndOfItem() async {
        guard !route.isHolding else { return }
        let controller = route.presented
        if isBook {
            await books.sleepAtEndOfChapter()
            return
        }
        books.forgetChapterSleep()
        if let group = controller.group {
            await sonos.sleepAtEndOfTrack(group: group)
        } else {
            LocalPlaybackService.shared.sleepAtEndOfTrack()
        }
    }

    // MARK: - Routes

    /// As Play On switches: This Mac or a group, the free tier's locked ones
    /// opening the paywall instead. Play On's Ask is a prompt a menu can't
    /// put up, so it takes the prompt's first answer, Move.
    private func switchRoute(to id: String) {
        // The menu checked the choice itself as it was made. Sent again
        // whatever came of it, so a choice turned down or gone nowhere (the
        // paywall, a group gone meanwhile) isn't left checked.
        defer {
            lastState = nil
            push(makeState())
        }
        let target: PlayDestination = id == DockMenuState.deviceRouteID ? .device : .group(id)
        guard target != route.destination else { return }
        let gate = FeatureGate.shared
        if target == .device, !gate.isAvailable(.onDevicePlayback) {
            if gate.needsSuper(.onDevicePlayback) {
                presentPaywall(for: .onDevicePlayback)
            }
            return
        }
        if let groupID = target.groupID, !gate.isGroupUnlocked(groupID) {
            presentPaywall(for: .allRooms)
            return
        }
        route.switchTo(target, carrying: QueueTransferPreference.current != .never)
    }

    /// The paywall over Cue's window, brought back first if it was closed.
    private func presentPaywall(for feature: GatedFeature) {
        bringCueForward()
        Task { @MainActor in
            // A window brought back takes a moment to have a scene to
            // present from.
            for _ in 0..<30 where !Self.hasActiveWindow {
                try? await Task.sleep(for: .milliseconds(100))
            }
            FeatureGate.shared.presentPaywall(PaywallReason(feature: feature))
        }
    }

    private static var hasActiveWindow: Bool {
        UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
    }

    /// Dock-menu item clicks (unlike dock-icon clicks) don't fire
    /// `applicationShouldHandleReopen`, so the Catalyst scene isn't brought
    /// back when the window was closed. Asks for it explicitly; the renderer
    /// has already activated the app.
    private func bringCueForward() {
        let session = UIApplication.shared.openSessions.first { $0.role == .windowApplication }
        UIApplication.shared.requestSceneSessionActivation(session, userActivity: nil, options: nil)
    }
}
#endif
