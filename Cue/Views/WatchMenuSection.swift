import SonosKit
import SwiftUI

/// "Add to Apple Watch" for a Plex or Subsonic album, playlist, artist or
/// song, or a Plex or Audiobookshelf book, and "Remove from Apple Watch"
/// once it's there. The watch looks it up and downloads it by itself (see
/// `WatchSyncService`). Nothing shows without a paired watch that has Cue
/// on it.
struct WatchMenuSection: View {
    @Environment(AlertService.self) private var alertService

    let item: PlayableContent

    var body: some View {
        let watch = WatchSyncService.shared
        if watch.canAdd(item) {
            if watch.isOnWatch(item) {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    watch.remove(item)
                    alertService.showAlertContent(with: item, subtitle: "Removed from Apple Watch", symbolName: "applewatch.slash")
                } label: {
                    Label("Remove from Apple Watch", systemImage: "applewatch.slash")
                }
            } else {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    guard FeatureGate.shared.unlock(.download(of: item)) else { return }
                    watch.add(item)
                    // The free songs are shared with this iPhone: with none
                    // left, the watch keeps the pick and waits for room.
                    if item.content.type != .audiobook, DownloadManager.shared.isAtFreeLimit {
                        LocalDownloadMenuSection.offerSuperForDownloads(detail: "\(item.title) is on its way to your Apple Watch, but its songs wait there for room. Cue Super makes room for them.")
                    } else {
                        alertService.showAlertContent(with: item, subtitle: "Downloading on Apple Watch", symbolName: "applewatch")
                    }
                } label: {
                    Label("Add to Apple Watch", systemImage: "applewatch")
                }
            }
        }
    }
}
