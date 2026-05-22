import Foundation

/// Commands the dock menu can send back to the app. Plain `@objc` enum so it
/// crosses the MacGlue bundle boundary without bridging cost.
@objc enum DockCommand: Int, CaseIterable {
    case playPause
    case previous
    case next
    case volumeUp
    case volumeDown
    case toggleRepeat
    case toggleShuffle
    case toggleCrossfade
    case toggleMute
    case muteAll
    case unmuteAll
    case toggleFavorite
    case openSpeaker
    /// Sets a sleep timer for the remaining time of the current track.
    case sleepAtEndOfTrack
}

/// The dock-menu surface the bundle exposes. Owned by `DockMenuRenderer`
/// inside MacGlue and consumed by `DockMenuCoordinator` on the app side.
/// Everything crosses the bundle boundary as ObjC-bridgeable types
/// (primitives, strings, arrays of strings).
@objc(DockMenuRenderable)
protocol DockMenuRenderable: NSObjectProtocol {
    /// One-time setup: swizzles `applicationDockMenu(_:)` into the
    /// Catalyst-installed NSApplicationDelegate so right-clicking the dock
    /// icon shows our menu instead of Catalyst's default.
    func setupDockMenu()

    /// Push the full menu state in one call. Cheap; safe to invoke often.
    /// All `Bool` flags should be `false` when no speaker is selected.
    /// - Parameters:
    ///   - volume: Group volume 0–100, shown as a header above Volume Up/Down.
    ///   - sleepMinutesRemaining: Minutes left on the sleep timer, or 0 when
    ///     no timer is set.
    func updateDockMenu(
        speakerName: String?,
        trackTitle: String?,
        trackArtist: String?,
        isPlaying: Bool,
        isRepeatAll: Bool,
        isShuffle: Bool,
        isCrossfade: Bool,
        isMuted: Bool,
        volume: Int,
        favoriteSupported: Bool,
        sleepMinutesRemaining: Int,
        groupIDs: [String],
        groupNames: [String],
        selectedGroupID: String?
    )

    func setDockCommandHandler(_ handler: @escaping (DockCommand) -> Void)
    /// Argument is a coordinator ID matching one of the `groupIDs` last
    /// supplied to `updateDockMenu`.
    func setSwitchGroupHandler(_ handler: @escaping (String) -> Void)
    /// Argument is the sleep-timer duration in minutes; 0 cancels the timer.
    func setSleepTimerHandler(_ handler: @escaping (Int) -> Void)
    /// Fired each time the user opens the dock menu — a non-blocking hook for
    /// the app to nudge a refresh so the cache is current for the next open.
    func setMenuWillOpenHandler(_ handler: @escaping () -> Void)
}
