import Foundation

/// What the watch does to match a library: the songs to fetch, in the
/// library's order, and the files to delete because no collection holds
/// them any more.
public struct WatchSyncPlan: Equatable, Sendable {
    public var toDownload: [String]
    public var toRemove: [String]

    public init(toDownload: [String], toRemove: [String]) {
        self.toDownload = toDownload
        self.toRemove = toRemove
    }

    /// `present` is every song the watch has an entry for, in any state.
    public static func make(library: WatchLibrary, present: Set<String>) -> WatchSyncPlan {
        let wanted = library.wantedKeys
        let wantedSet = Set(wanted)
        return WatchSyncPlan(
            toDownload: wanted.filter { !present.contains($0) },
            toRemove: present.filter { !wantedSet.contains($0) }.sorted()
        )
    }

    public var isEmpty: Bool { toDownload.isEmpty && toRemove.isEmpty }
}
