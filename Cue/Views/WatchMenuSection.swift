import SonosKit
import SwiftUI

/// "Add to Apple Watch" for a Plex or Subsonic album, playlist, artist or
/// song, and "Remove from Apple Watch" once it's there. The watch downloads
/// it by itself (see `WatchSyncService`). Nothing shows without a paired
/// watch that has Cue on it.
struct WatchMenuSection: View {
    @Environment(AlertService.self) private var alertService

    let item: PlayableContent

    var body: some View {
        let watch = WatchSyncService.shared
        if watch.canAdd(item) {
            if watch.isAdding(item) {
                Label("Adding to Apple Watch…", systemImage: "applewatch")
            } else if watch.isOnWatch(item) {
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
                    guard FeatureGate.shared.unlock(.downloads) else { return }
                    Task { @MainActor in
                        let count = await watch.add(item)
                        if count == 0 {
                            alertService.showAlert(with: "Nothing to put on Apple Watch", imageName: "applewatch")
                        } else if item.content.type == .track {
                            alertService.showAlertContent(with: item, subtitle: "Downloading on Apple Watch", symbolName: "applewatch")
                        } else {
                            alertService.showAlertContent(with: item, subtitle: "Downloading \(count) songs on Apple Watch", symbolName: "applewatch")
                        }
                    }
                } label: {
                    Label("Add to Apple Watch", systemImage: "applewatch")
                }
            }
        }
    }
}
