import Foundation

public enum AppStorageKeys {
    /// The search's selected services as one ordered comma-separated list,
    /// primary first (up to 3). Replaced the split `mediaService` +
    /// `searchAlsoServices` keys — deliberately not migrated; the selection
    /// resets once and users re-pick.
    public static let selectedSearchServices = "\(Prefix.id).selectedSearchServices"
    public static let browseMediaService = "\(Prefix.id).browseMediaService"
    /// The music providers the user has added to the tab view, in order —
    /// raw `MediaSearchService` values. Each gets a tab of its own (and, on
    /// iPad and Mac, a sidebar section split into its collections).
    public static let tabProviders = "\(Prefix.id).tabProviders"
    /// The sidebar edits the system lets the user make to those tabs — hiding
    /// and reordering — as a `TabViewCustomization`.
    public static let tabViewCustomization = "\(Prefix.id).tabViewCustomization"
    /// The Files provider's folder, as a security-scoped bookmark (`Data`)
    /// of the folder the user picked — on this device or in iCloud Drive.
    public static let filesFolderBookmark = "\(Prefix.id).filesFolderBookmark"
    /// That folder's name, kept beside the bookmark so the Services row can
    /// name it without resolving the bookmark first.
    public static let filesFolderName = "\(Prefix.id).filesFolderName"
    public static let appleMusicAuthorized = "\(Prefix.id).appleMusicAuthorized"
    public static let colorScheme = "\(Prefix.id).colorScheme"
    public static let speedLaunchNowPlaying = "\(Prefix.id).speedLaunchNowPlaying"
    public static let queueMode = "\(Prefix.id).queueMode"
    public static let showArtworkOnly = "\(Prefix.id).showArtworkOnly"
    public static let queueInspectorVisible = "\(Prefix.id).queueInspectorVisible"
    /// Width in points of the trailing queue panel, so a drag-to-resize
    /// survives relaunch.
    public static let queuePanelWidth = "\(Prefix.id).queuePanelWidth"
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
    /// The device's volume buttons — and the Lock Screen / Control Center
    /// slider, which are the same system volume — control the Sonos group
    /// instead of this device. **On** when unset: it's what people expect of a
    /// speaker controller, and the surface it drives (`Preferences ▸ Lock
    /// Screen ▸ Now Playing`) is itself the default with Super.
    ///
    /// It means one thing in both places that read it: *while Cue is your Lock
    /// Screen player, this device's volume controls the speaker.* Both the Lock
    /// Screen path and the player screen's `hardwareVolumeControl` therefore
    /// require `lockScreenNowPlaying` and an active subscription as well —
    /// don't add a reader that takes this key on its own. The row that sets it
    /// is shown only under Now Playing and only with Super, so a behaviour
    /// gated more loosely than the switch is one the user can't reach a control
    /// for.
    ///
    /// Read it through `UserDefaults.hardwareVolumeButtonsEnabled`, never
    /// `bool(forKey:)`, which reads unset as off and would leave the default
    /// unreachable.
    ///
    /// Defaulting this on is only safe because `HardwareVolumeService` stands
    /// the bridge down on any route that isn't the phone's own speaker, and
    /// refuses a volume jump larger than a hand could make. Read
    /// `Docs/LockScreenNowPlaying.md` § "Where the phone is" before weakening
    /// either — the report that produced them was a Sonos pair left at 100%
    /// volume all day.
    public static let useHardwareVolumeButtons = "\(Prefix.id).useHardwareVolumeButtons"
    /// Mirrors the playing group onto the Lock Screen / Control Center Now
    /// Playing card by holding a silent audio session. **On** when unset: it's
    /// the default Lock Screen surface for Cue Super. Read it through
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

    /// Same shape, same reason — see `AppStorageKeys.useHardwareVolumeButtons`.
    /// The explicit-`false` case matters more here than for the surface itself:
    /// it's how someone who turned this off after their speakers were set to
    /// full volume keeps it off through the update that changed the default.
    var hardwareVolumeButtonsEnabled: Bool {
        get { object(forKey: AppStorageKeys.useHardwareVolumeButtons) as? Bool ?? true }
        set { set(newValue, forKey: AppStorageKeys.useHardwareVolumeButtons) }
    }
}
