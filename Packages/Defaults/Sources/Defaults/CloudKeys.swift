import Foundation

/// Cue keeps its own iCloud key-value store: the ubiquity identifier is derived
/// from `BUNDLE_ID`, so nothing here reads or writes anything Clic can see.
///
/// Sharing play history with Clic was tried and backed out. Pointing the
/// ubiquity identifier at Clic's store does work — each app writing its own key
/// and unioning on read, since `@CloudStorage` stores the whole list as one
/// blob and a shared key would be last-writer-wins — but on macOS reading
/// another app's store trips the "access data from other apps" privacy prompt
/// every launch. If this is revisited, that prompt is the problem to solve
/// first, not the key layout.
public enum CloudKeys {
    public static let playHistory = "\(Prefix.id).playHistory"
    public static let scenes = "com.cue.scenes"
    public static let hasSubscription =  "com.cue.subscriptions"
}
