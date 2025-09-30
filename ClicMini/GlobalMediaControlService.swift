import Foundation
import KeyboardShortcuts
import SonosKitMini


final class GlobalMediaControlService {
    static let shared = GlobalMediaControlService()
    
    // Generic key repeat system
    private var keyRepeatTasks: [KeyboardShortcuts.Name: Task<Void, Never>] = [:]
    
    private init() {
        setupKeyboardShortcuts()
    }
    
    deinit {
        // Cancel all active repeat tasks
        keyRepeatTasks.values.forEach { $0.cancel() }
        keyRepeatTasks.removeAll()
    }
    
    private func setupKeyboardShortcuts() {
        // Volume controls with key repeat
        setupKeyRepeat(for: .volumeUp, interval: 0.1) { [weak self] in
            await self?.performVolumeUp()
        }
        
        setupKeyRepeat(for: .volumeDown, interval: 0.1) { [weak self] in
            await self?.performVolumeDown()
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
        action: @escaping @MainActor () async -> Void
    ) {
        // Setup onKeyDown to start repeating
        KeyboardShortcuts.onKeyDown(for: shortcut) { [weak self] in
            self?.startKeyRepeat(for: shortcut, interval: interval, action: action)
        }
        
        // Setup onKeyUp to stop repeating
        KeyboardShortcuts.onKeyUp(for: shortcut) { [weak self] in
            self?.stopKeyRepeat(for: shortcut)
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
        guard let group = await getPlayingGroup() else { return }
        await SonosMiniService.shared.setRelativeVolume(ip: group.ip, volume: 2)
        await volumeUp(group: group, volume: group.groupVolume + 2)
        await updateVolume(for: group)
    }
    
    @MainActor
    private func performVolumeDown() async {
        guard let group = await getPlayingGroup() else { return }
        await SonosMiniService.shared.setRelativeVolume(ip: group.ip, volume: -2)
        await volumeDown(group: group, volume: max(0, group.groupVolume - 2))
        await updateVolume(for: group)
    }
    
    @MainActor
    private func performNextTrack() async {
        guard let group = await getPlayingGroup() else { return }
        await SonosMiniService.shared.next(ip: group.ip)
        guard let track = await SonosMiniService.shared.getTrack(ip: group.ip) else { return }
        await nextTrack(group: group, track: track)
        guard let index = SonosMiniService.shared.devices.firstIndex(where: { $0.id == group.id }) else {
            return
        }
        SonosMiniService.shared.devices[index].track = track
    }
    
    @MainActor
    private func performPreviousTrack() async {
        guard let group = await getPlayingGroup() else { return }
        await SonosMiniService.shared.previous(ip: group.ip)
        guard let track = await SonosMiniService.shared.getTrack(ip: group.ip) else { return }
        await previousTrack(group: group, track: track)
        guard let index = SonosMiniService.shared.devices.firstIndex(where: { $0.id == group.id }) else {
            return
        }
        SonosMiniService.shared.devices[index].track = track
    }
    
    // MARK: - UI Helper Methods
    
    @MainActor
    private func volumeUp(group: SonosDevice, volume: Double) async {
        // Extend window visibility for continuous volume changes
        HudWindowManager.shared.extendVisibility()
        HudWindowManager.shared.showMediaIndicator(
            speakerName: group.nameWithCount,
            action: .volumeUp(volume: volume),
            isPlaying: true  // Always show volume controls
        )
        return
    }
    
    @MainActor
    private func volumeDown(group: SonosDevice, volume: Double) async {
        // Extend window visibility for continuous volume changes
        HudWindowManager.shared.extendVisibility()
        
        // Show volume indicator
        HudWindowManager.shared.showMediaIndicator(
            speakerName: group.nameWithCount,
            action: .volumeDown(volume: volume),
            isPlaying: true  // Always show volume controls
        )
    }
    
    @MainActor
    private func nextTrack(group: SonosDevice, track: SonosTrack) async {
        HudWindowManager.shared.extendVisibility()
        
        // Show volume indicator
        HudWindowManager.shared.showMediaIndicator(
            speakerName: group.nameWithCount,
            action: .nextTrack(trackName: track.name, imageURL: track.sonosAlbumArtURL),
            isPlaying: true  // Always show volume controls
        )
    }
    
    @MainActor
    private func previousTrack(group: SonosDevice, track: SonosTrack) async {
        HudWindowManager.shared.extendVisibility()
        
        // Show volume indicator
        HudWindowManager.shared.showMediaIndicator(
            speakerName: group.nameWithCount,
            action: .previousTrack(trackName: track.name, imageURL: track.sonosAlbumArtURL),
            isPlaying: true  // Always show volume controls
        )
    }
    
    private func getPlayingGroup() async -> SonosDevice? {
        // Check if there's a pinned speaker first
        if let pinnedId = await MiniSettingsService.shared.pinnedSpeakerId,
           let pinnedDevice = await SonosMiniService.shared.devices.first(where: { $0.id == pinnedId }) {
            return pinnedDevice
        }
        
        // Fall back to the original logic
        guard let id = await SonosMiniService.shared.getNowPlayingID() else { return nil }
        guard let group = await SonosMiniService.shared.devices.first(where: { $0.id == id }) else { return nil }
        return group
    }
    
    @MainActor
    private func updateVolume(for device: SonosDevice) async {
        guard let index = SonosMiniService.shared.devices.firstIndex(where: { $0.id == device.id }) else { return }
        guard let groupVolume = try? await SonosMiniService.shared.getGroupVolume(ip: device.ip) else { return }
        SonosMiniService.shared.devices[index].groupVolume = groupVolume
    }
}
