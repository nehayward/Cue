import SonosKit
import SwiftUI
import UIKit
import WatchSync

/// "Add to Apple Watch" for a Plex or Subsonic album, playlist, artist or
/// song, and "Remove from Apple Watch" once it's there. The watch downloads
/// it by itself (see `WatchSyncService`). The first add asks what quality
/// songs should go at. Nothing shows without a paired watch that has Cue
/// on it.
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
                    if watch.needsQualityChoice {
                        WatchQualityPrompt.present { quality in
                            guard let quality else { return }
                            watch.setQuality(quality)
                            add()
                        }
                    } else {
                        add()
                    }
                } label: {
                    Label("Add to Apple Watch", systemImage: "applewatch")
                }
            }
        }
    }

    private func add() {
        let alertService = alertService
        Task { @MainActor in
            let count = await WatchSyncService.shared.add(item)
            if count == 0 {
                alertService.showAlert(with: "Nothing to put on Apple Watch", imageName: "applewatch")
            } else if item.content.type == .track {
                alertService.showAlertContent(with: item, subtitle: "Downloading on Apple Watch", symbolName: "applewatch")
            } else {
                alertService.showAlertContent(with: item, subtitle: "Downloading \(count) songs on Apple Watch", symbolName: "applewatch")
            }
        }
    }
}

/// The question put the first time something goes on the watch: what
/// quality songs should go at. A UIKit alert on whatever is on top, after a
/// beat, because the tap comes from a menu that's still closing (as with
/// `CellularDownloadPrompt`). Nil means the person backed out.
@MainActor
enum WatchQualityPrompt {
    static func present(answer: @escaping @MainActor (WatchDownloadQuality?) -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard let presenter = topViewController() else {
                answer(.recommended)
                return
            }
            let sizes = WatchDownloadQuality.allCases.map { "\($0.title): \($0.detail)." }.joined(separator: "\n")
            let alert = UIAlertController(
                title: "Quality on Apple Watch",
                message: "Your watch has much less room than your iPhone, so songs can be converted to MP3 as they download.\n\n\(sizes)\n\nYou can change this later in Settings › Storage › Apple Watch.",
                preferredStyle: .alert
            )
            for quality in WatchDownloadQuality.allCases {
                let title = quality == .recommended ? "\(quality.title) (Recommended)" : quality.title
                alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                    answer(quality)
                })
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                answer(nil)
            })
            alert.preferredAction = alert.actions.first { $0.title?.hasPrefix(WatchDownloadQuality.recommended.title) == true }
            presenter.present(alert, animated: true)
        }
    }

    /// The controller at the top of the key window's presentation chain,
    /// passing over one already on its way out.
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.filter { $0.activationState == .foregroundActive }.flatMap(\.windows)
            + scenes.flatMap(\.windows)
        let window = windows.first { $0.isKeyWindow } ?? windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
