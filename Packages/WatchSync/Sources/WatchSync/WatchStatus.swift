import Foundation

/// What the watch tells the iPhone after each change: the library revision
/// it's working from, how much of each collection is on it, and the room
/// it takes — so the iPhone can show "12 of 14 on Apple Watch" without
/// asking. Counts rather than song lists, so it stays small however big
/// the library grows: application context is meant for a few kilobytes.
public struct WatchStatus: Codable, Equatable, Sendable {
    public var libraryRevision: Int
    /// Songs on the watch from each collection, by collection key.
    public var downloadedByCollection: [String: Int]
    /// Songs on the watch, each once.
    public var downloadedCount: Int
    /// Songs still to come down (queued or under way).
    public var pendingCount: Int
    /// Songs that failed and wait for a retry.
    public var failedCount: Int
    public var bytesUsed: Int64
    public var updatedAt: Date

    public init(
        libraryRevision: Int,
        downloadedByCollection: [String: Int],
        downloadedCount: Int,
        pendingCount: Int,
        failedCount: Int,
        bytesUsed: Int64,
        updatedAt: Date
    ) {
        self.libraryRevision = libraryRevision
        self.downloadedByCollection = downloadedByCollection
        self.downloadedCount = downloadedCount
        self.pendingCount = pendingCount
        self.failedCount = failedCount
        self.bytesUsed = bytesUsed
        self.updatedAt = updatedAt
    }

    /// The status of a library on a watch that has `isDownloaded` songs.
    public init(
        library: WatchLibrary,
        isDownloaded: (String) -> Bool,
        pendingCount: Int,
        failedCount: Int,
        bytesUsed: Int64,
        updatedAt: Date
    ) {
        var byCollection: [String: Int] = [:]
        for collection in library.collections {
            byCollection[collection.key] = collection.trackKeys.filter(isDownloaded).count
        }
        self.init(
            libraryRevision: library.revision,
            downloadedByCollection: byCollection,
            downloadedCount: library.wantedKeys.filter(isDownloaded).count,
            pendingCount: pendingCount,
            failedCount: failedCount,
            bytesUsed: bytesUsed,
            updatedAt: updatedAt
        )
    }
}
