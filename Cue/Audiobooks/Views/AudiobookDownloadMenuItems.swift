import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// The whole book on this device, from a menu: Download Book, or Remove
/// (Cancel while it comes down). At a glance rather than the progress: an
/// open menu redrawn with every bit of progress flickers.
struct AudiobookDownloadMenuItems: View {
    let book: PlayableContent

    @Environment(AlertService.self) private var alertService

    var body: some View {
        let manager = DownloadManager.shared
        if manager.canDownload(contentsOf: book) {
            switch manager.containerPresence(for: book) {
            case .downloaded:
                Button(role: .destructive) {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    manager.removeDownload(contentsOf: book)
                    alertService.showAlertContent(with: book, subtitle: "Removed from this device", symbolName: "trash")
                } label: {
                    Label("Remove Download", systemImage: "trash")
                }
            case .downloading:
                Button(role: .destructive) {
                    manager.removeDownload(contentsOf: book)
                } label: {
                    Label("Cancel Download", systemImage: "xmark.circle")
                }
            case nil:
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    guard FeatureGate.shared.unlock(.downloads) else { return }
                    Task { @MainActor in
                        await LocalDownloadMenuSection.download(book, alertService: alertService)
                    }
                } label: {
                    Label("Download Book", systemImage: "arrow.down.circle")
                }
            }
        }
    }
}
