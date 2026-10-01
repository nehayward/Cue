import Foundation

/// Cue keeps its own iCloud key-value store: the ubiquity identifier is derived
/// from `BUNDLE_ID`, so nothing here reads or writes another app's store.
///
/// Sharing a store with another app was tried and backed out: on macOS,
/// reading another app's store trips the "access data from other apps"
/// privacy prompt every launch. If this is revisited, that prompt is the
/// problem to solve first, not the key layout.
public enum CloudKeys {
    public static let playHistory = "\(Prefix.id).playHistory"
    public static let scenes = "com.cue.scenes"
    public static let hasSubscription =  "com.cue.subscriptions"
}
