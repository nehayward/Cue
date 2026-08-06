import Foundation

public enum AppStorageKeys {
    /// The search's selected services as one ordered comma-separated list,
    /// primary first (up to 3). Replaced the split `mediaService` +
    /// `searchAlsoServices` keys — deliberately not migrated; the selection
    /// resets once and users re-pick.
    public static let selectedSearchServices = "\(Prefix.id).selectedSearchServices"
    public static let browseMediaService = "\(Prefix.id).browseMediaService"
    public static let appleMusicAuthorized = "\(Prefix.id).appleMusicAuthorized"
    public static let colorScheme = "\(Prefix.id).colorScheme"
    public static let speedLaunchNowPlaying = "\(Prefix.id).speedLaunchNowPlaying"
    public static let queueMode = "\(Prefix.id).queueMode"
    public static let showArtworkOnly = "\(Prefix.id).showArtworkOnly"
    public static let queueInspectorVisible = "\(Prefix.id).queueInspectorVisible"
    public static let savedGroupID = "\(Prefix.id).queueInspectorGroupID"
    public static let defaultPlayAction = "\(Prefix.id).defaultPlayAction"
    public static let lastPlaylistID = "\(Prefix.id).lastPlaylistID"
    public static let lastPlaylistTitle = "\(Prefix.id).lastPlaylistTitle"
    public static let lastPlaylistService = "\(Prefix.id).lastPlaylistService"
    public static let recentPlaylistIDs = "\(Prefix.id).recentPlaylistIDs"
    public static let addToPlaylistSegment = "\(Prefix.id).addToPlaylistSegment"
    public static let recentlyViewed = "\(Prefix.id).recentlyViewed"
    public static let recentQueries = "\(Prefix.id).recentQueries"
    public static let lastSeenWhatsNewVersion = "\(Prefix.id).lastSeenWhatsNewVersion"
    public static let lastSeenSettingsBadgeVersion = "\(Prefix.id).lastSeenSettingsBadgeVersion"
    public static let latestReleaseVersion = "\(Prefix.id).latestReleaseVersion"
    public static let latestReleaseHeadline = "\(Prefix.id).latestReleaseHeadline"
    public static let useHardwareVolumeButtons = "\(Prefix.id).useHardwareVolumeButtons"
    /// Mirrors the playing group onto the Lock Screen / Control Center Now
    /// Playing card by holding a silent audio session. **On** when unset: it's
    /// the default Lock Screen surface for Clic Super. Read it through
    /// `UserDefaults.lockScreenNowPlayingEnabled`, never `bool(forKey:)`, which
    /// reads unset as off and would leave the default unreachable.
    ///
    /// Being on is not enough to run — `NowPlayingSessionService.isEnabled` also
    /// requires an active subscription, so an unsubscribed user with the default
    /// keeps Live Activities and nothing takes over their audio.
    public static let lockScreenNowPlaying = "\(Prefix.id).lockScreenNowPlaying"
}

public extension UserDefaults {
    /// One accessor, so the unset-means-on default can't be got wrong at a call
    /// site. An explicit `false` — someone who turned it off — still reads false.
    var lockScreenNowPlayingEnabled: Bool {
        get { object(forKey: AppStorageKeys.lockScreenNowPlaying) as? Bool ?? true }
        set { set(newValue, forKey: AppStorageKeys.lockScreenNowPlaying) }
    }
}
