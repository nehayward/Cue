import Foundation
import Observation
import SonosKit

#if os(iOS)
import MediaPlayer

/// Answers "does the Music app hold a local, downloaded copy of this song?".
///
/// Third-party apps can't download Apple Music tracks themselves (the files
/// are DRM'd and the API to initiate a download doesn't exist), but the media
/// library exposes each library item's cloud status — `isCloudItem == false`
/// means the file is on this device — and `playbackStoreID` lines up with the
/// catalog ids our search results carry. So while we can't *make* a track
/// downloaded, we can badge the ones that are, and playback of those through
/// `ApplicationMusicPlayer` works offline.
@MainActor
@Observable
final class AppleDownloadsIndex {
    static let shared = AppleDownloadsIndex()

    /// `playbackStoreID`s (Apple catalog ids) of songs with a local file.
    private(set) var downloadedStoreIDs: Set<String> = []

    @ObservationIgnored private var isRefreshing = false

    private init() {
        refreshIfNeeded()
    }

    func isDownloaded(_ item: PlayableContent) -> Bool {
        item.content.service == .apple && downloadedStoreIDs.contains(item.content.id)
    }

    /// Rebuilds the index off the main thread. Cheap enough to re-run when a
    /// menu opens; the guard just stops overlapping sweeps.
    func refreshIfNeeded() {
        guard !isRefreshing else { return }
        guard MPMediaLibrary.authorizationStatus() == .authorized else { return }
        isRefreshing = true
        Task.detached(priority: .utility) {
            let ids = Set(
                (MPMediaQuery.songs().items ?? [])
                    .filter { !$0.isCloudItem && $0.playbackStoreID != "0" }
                    .map(\.playbackStoreID)
            )
            await MainActor.run {
                AppleDownloadsIndex.shared.downloadedStoreIDs = ids
                AppleDownloadsIndex.shared.isRefreshing = false
            }
        }
    }
}
#else
/// Media-library queries only exist on iOS — elsewhere nothing reports as
/// downloaded, which just hides the badge.
@MainActor
@Observable
final class AppleDownloadsIndex {
    static let shared = AppleDownloadsIndex()
    var downloadedStoreIDs: Set<String> { [] }
    func isDownloaded(_ item: PlayableContent) -> Bool { false }
    func refreshIfNeeded() {}
}
#endif
