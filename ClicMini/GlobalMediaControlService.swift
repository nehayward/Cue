import Foundation
import KeyboardShortcuts
import SonosKitMini


final class GlobalMediaControlService {
    static let shared = GlobalMediaControlService()
    
    // Generic key repeat system
    private var keyRepeatTasks: [KeyboardShortcuts.Name: Task<Void, Never>] = [:]

    // MARK: Volume gesture state
    //
    // A volume "gesture" spans one keypress (or a held key-repeat run). We track
    // an optimistic target locally so the HUD updates instantly, and coalesce the
    // actual network writes into a throttled, absolute setGroupVolume so a fast
    // key-repeat can't backlog round-trips (which caused overshoot + HUD jitter).
    private var volumeGroup: SonosDevice?
    private var volumeTarget: Double?
    private var volumeGestureActive = false
    private var lastVolumeSentTarget: Int?
    private var volumeSendTask: Task<Void, Never>?

    // MARK: Skip state
    //
    // skipGeneration ensures a burst of next/previous taps only renders the final
    // resolved track, not stale ones.
    private var skipGeneration = 0

    // Caches only the *unpinned* now-playing lookup (the one networked call in
    // getPlayingGroup), with a short TTL so rapid skips stay snappy. A pinned
    // speaker is resolved locally every time and is never cached, so changing the
    // pin takes effect immediately. The TTL is the entire invalidation story.
    private var cachedNowPlaying: (group: SonosDevice, at: Date)?
    private let nowPlayingCacheTTL: TimeInterval = 5

    private init() {
        setupKeyboardShortcuts()
    }
    
    deinit {
        // Cancel all active repeat tasks
        keyRepeatTasks.values.forEach { $0.cancel() }
        keyRepeatTasks.removeAll()
    }
    
    private func setupKeyboardShortcuts() {
        // Volume controls with key repeat. onRelease ends the gesture so the next
        // press re-seeds the target from the speaker's real volume.
        setupKeyRepeat(for: .volumeUp, interval: 0.1) { [weak self] in
            await self?.performVolumeUp()
        } onRelease: { [weak self] in
            self?.endVolumeGesture()
        }

        setupKeyRepeat(for: .volumeDown, interval: 0.1) { [weak self] in
            await self?.performVolumeDown()
        } onRelease: { [weak self] in
            self?.endVolumeGesture()
        }
        
        // Media controls - single actions without repeat
        KeyboardShortcuts.onKeyUp(for: .nextTrack) { [weak self] in
            Task { @MainActor in
                await self?.performNextTrack()
            }
        }
        
        KeyboardShortcuts.onKeyUp(for: .previousTrack) { [weak self] in
            Task { @MainActor in
                await self?.performPreviousTrack()
            }
        }
        
        // Example: To add key repeat for other actions, simply call:
        // setupKeyRepeat(for: .someOtherKey, interval: 0.3) { [weak self] in
        //     await self?.performSomeAction()
        // }
    }
    
    // MARK: - Generic Key Repeat System
    
    /// Sets up a keyboard shortcut that repeats an action while the key is held down
    /// - Parameters:
    ///   - shortcut: The keyboard shortcut to monitor
    ///   - interval: Time interval between repeats (in seconds)
    ///   - action: The async action to perform
    private func setupKeyRepeat(
        for shortcut: KeyboardShortcuts.Name,
        interval: TimeInterval,
        action: @escaping @MainActor () async -> Void,
        onRelease: (() -> Void)? = nil
    ) {
        // Setup onKeyDown to start repeating
        KeyboardShortcuts.onKeyDown(for: shortcut) { [weak self] in
            self?.startKeyRepeat(for: shortcut, interval: interval, action: action)
        }

        // Setup onKeyUp to stop repeating
        KeyboardShortcuts.onKeyUp(for: shortcut) { [weak self] in
            self?.stopKeyRepeat(for: shortcut)
            onRelease?()
        }
    }
    
    /// Starts repeating an action for a specific key
    private func startKeyRepeat(
        for shortcut: KeyboardShortcuts.Name,
        interval: TimeInterval,
        action: @escaping @MainActor () async -> Void
    ) {
        // Cancel any existing repeat task for this key
        stopKeyRepeat(for: shortcut)
        
        // Create a new repeating task
        keyRepeatTasks[shortcut] = Task { @MainActor in
            // Execute immediately
            await action()
            
            // Then repeat at intervals while task is not cancelled
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if !Task.isCancelled {
                    await action()
                }
            }
        }
    }
    
    /// Stops repeating for a specific key
    private func stopKeyRepeat(for shortcut: KeyboardShortcuts.Name) {
        keyRepeatTasks[shortcut]?.cancel()
        keyRepeatTasks.removeValue(forKey: shortcut)
    }
    
    // MARK: - Action Methods
    
    @MainActor
    private func performVolumeUp() async {
        await adjustVolume(by: 1)
    }

    @MainActor
    private func performVolumeDown() async {
        await adjustVolume(by: -1)
    }

    /// Bumps the optimistic volume target, updates the HUD instantly, and lets the
    /// throttled sender push the absolute value to the speaker.
    @MainActor
    private func adjustVolume(by delta: Double) async {
        // Start of a gesture: resolve the group and seed from its real volume.
        if !volumeGestureActive {
            guard let group = await getPlayingGroup() else { return }
            volumeGestureActive = true
            volumeGroup = group
            volumeTarget = group.groupVolume
        }
        guard let group = volumeGroup else { return }

        let newTarget = min(100, max(0, (volumeTarget ?? group.groupVolume) + delta))
        volumeTarget = newTarget

        // Instant feedback — drive the HUD purely off the local target.
        HudWindowManager.shared.showMediaIndicator(
            speakerName: group.nameWithCount,
            action: delta >= 0 ? .volumeUp(volume: newTarget) : .volumeDown(volume: newTarget),
            isPlaying: true
        )

        ensureVolumeSender(ip: group.ip)
    }

    /// Coalesces volume writes: sends the latest absolute target immediately, then
    /// at most once per throttle interval while it keeps moving, then a trailing
    /// send once it settles. Absolute (not relative) so coalesced sends converge.
    @MainActor
    private func ensureVolumeSender(ip: String) {
        guard volumeSendTask == nil else { return }
        volumeSendTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let target = volumeTarget else { break }
                let value = Int(target.rounded())
                if lastVolumeSentTarget != value {
                    lastVolumeSentTarget = value
                    await SonosMiniService.shared.setGroupVolume(ip: ip, volume: value)
                    try? await Task.sleep(for: .milliseconds(150))
                } else {
                    break // caught up — the final value has been sent
                }
            }
            volumeSendTask = nil
            // Reconcile the real device volume so the next gesture seeds correctly.
            await reconcileVolume(ip: ip)
        }
    }

    /// Ends the current volume gesture; the next keypress re-seeds from the speaker.
    private func endVolumeGesture() {
        volumeGestureActive = false
    }

    @MainActor
    private func reconcileVolume(ip: String) async {
        guard let real = try? await SonosMiniService.shared.getGroupVolume(ip: ip) else { return }
        guard let index = SonosMiniService.shared.devices.firstIndex(where: { $0.ip == ip }) else { return }
        SonosMiniService.shared.devices[index].groupVolume = real
    }
    
    @MainActor
    private func performNextTrack() async {
        await skip(forward: true)
    }

    @MainActor
    private func performPreviousTrack() async {
        await skip(forward: false)
    }

    /// Skips forward/back. Shows feedback instantly (keeping the current artwork
    /// with a spinner) without waiting on the network, fires the skip command,
    /// then fills in the resolved track. Rapid repeated taps stay snappy: the
    /// HUD updates immediately each tap, and a generation token ensures only the
    /// latest tap's resolved track is shown.
    @MainActor
    private func skip(forward: Bool) async {
        // getPlayingGroup is instant for a pinned speaker and TTL-cached otherwise,
        // so this stays snappy without going stale.
        guard let group = await getPlayingGroup() else { return }

        let direction: MediaIndicatorView.MediaAction.Direction = forward ? .next : .previous

        // Keep the current track's artwork/title up with a spinner while we skip.
        let current = SonosMiniService.shared.devices.first(where: { $0.id == group.id })?.track ?? group.track
        HudWindowManager.shared.showMediaIndicator(
            speakerName: group.nameWithCount,
            action: .track(direction: direction, title: current.name, artist: current.artist,
                           albumName: current.album, imageURL: current.artworkURL, loading: true),
            isPlaying: true,
            displayDuration: 5
        )

        skipGeneration &+= 1
        let generation = skipGeneration

        if forward {
            await SonosMiniService.shared.next(ip: group.ip)
        } else {
            await SonosMiniService.shared.previous(ip: group.ip)
        }

        guard let track = await SonosMiniService.shared.getTrack(ip: group.ip) else { return }
        // A newer tap superseded us — let it own the HUD.
        guard generation == skipGeneration else { return }

        HudWindowManager.shared.showMediaIndicator(
            speakerName: group.nameWithCount,
            action: .track(direction: direction, title: track.name, artist: track.artist,
                           albumName: track.album, imageURL: track.artworkURL, loading: false),
            isPlaying: true,
            displayDuration: 5
        )

        if let index = SonosMiniService.shared.devices.firstIndex(where: { $0.id == group.id }) {
            SonosMiniService.shared.devices[index].track = track
        }
    }

    @MainActor
    private func getPlayingGroup() async -> SonosDevice? {
        // Pinned speaker: a local lookup that's always current, so a pin change is
        // honored immediately. Not cached.
        if let pinnedId = await MiniSettingsService.shared.pinnedSpeakerId,
           let pinnedDevice = await SonosMiniService.shared.devices.first(where: { $0.id == pinnedId }) {
            return pinnedDevice
        }

        // Unpinned: getNowPlayingID is networked, so reuse a recent result while it
        // is still fresh. We re-read the live device by id each time so its track
        // and volume stay current even on a cache hit.
        if let cached = cachedNowPlaying,
           Date().timeIntervalSince(cached.at) < nowPlayingCacheTTL,
           let live = await SonosMiniService.shared.devices.first(where: { $0.id == cached.group.id }) {
            return live
        }

        guard let id = await SonosMiniService.shared.getNowPlayingID() else { return nil }
        guard let group = await SonosMiniService.shared.devices.first(where: { $0.id == id }) else { return nil }
        cachedNowPlaying = (group, Date())
        return group
    }
}
