import Foundation

public enum GroupStorageKeys {
    public static let storage = UserDefaults(suiteName: GroupStorageKeys.name)
    
    public static let name = "group.com.clic"
    public static let hasOnboarded = "\(Prefix.id).hasOnboarded"
    
    public static let spotifyMusicTokenID = "\(Prefix.id).spotifyMusicTokenID"
    public static let appleMusicTokenID = "\(Prefix.id).appleMusicTokenID"

    /// Whether Live Activities may be started at all. **On** when unset — this
    /// switch arrived after the feature shipped, so absence has to mean the
    /// behaviour every existing install already has. Read it through
    /// `liveActivitiesEnabled`, never `bool(forKey:)`, which reads unset as off.
    ///
    /// In the shared suite rather than `AppStorageKeys` because the widget
    /// intents (`CreateLiveActivityIntent`, `PlaybackIntent`, …) start activities
    /// from the extension's process, and `UserDefaults.standard` there is a
    /// different container — the switch would have been invisible to exactly the
    /// call sites that bypass the app.
    public static let liveActivities = "\(Prefix.id).liveActivities"
    /// Set when Lock Screen Controls is what turned Live Activities off, so
    /// turning Lock Screen Controls back off restores them. Without it the user
    /// ends up with neither Lock Screen surface and nothing to suggest why.
    public static let liveActivitiesSuspendedByLockScreen = "\(Prefix.id).liveActivitiesSuspendedByLockScreen"

    /// Non-optional accessor. Falls back to `.standard` so a missing app-group
    /// entitlement degrades to app-local behaviour instead of dropping writes.
    public static var defaults: UserDefaults { storage ?? .standard }
}

public extension UserDefaults {
    /// Live Activities are on unless something turned them off. One accessor, so
    /// the unset-means-on default can't be got wrong at a call site.
    var liveActivitiesEnabled: Bool {
        get { object(forKey: GroupStorageKeys.liveActivities) as? Bool ?? true }
        set { set(newValue, forKey: GroupStorageKeys.liveActivities) }
    }
}
