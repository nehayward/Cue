import SonosKit

/// The Sonos music library's Songs list status, built by the library's front
/// page and its Songs tab alike.
@MainActor
enum LocalLibraryLists {
    /// The line under the Songs title: how far the one-time index sync has
    /// got while it runs, and how many tracks the library holds once it is
    /// there.
    static func songSyncStatus(browseService: LibraryBrowseService) -> () -> String? {
        {
            guard browseService.isSyncingSongs else {
                guard let count = browseService.songCount, count > 0 else { return nil }
                return count == 1 ? "1 song" : "\(count.formatted()) songs"
            }

            let synced = browseService.syncedSongCount
            guard let total = browseService.librarySongCount, total > 0 else {
                return synced == 0 ? "Loading library…" : "\(synced.formatted()) songs"
            }
            return "\(min(synced, total).formatted()) of \(total.formatted())"
        }
    }
}
