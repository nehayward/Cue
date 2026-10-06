import SonosKit
import SwiftUI

/// The glass button beside Play and Shuffle on an album or playlist screen
/// that keeps the whole thing on this device: an arrow to start, a ring
/// while it comes down (with Cancel behind it), a filled arrow once it's
/// here (with Remove behind it). Only for what the download manager can
/// take whole — a Plex or Subsonic album, playlist or artist.
struct ContainerDownloadButton: View {
    @Environment(AlertService.self) private var alertService

    let item: PlayableContent

    @State private var isQueuing = false

    var body: some View {
        let manager = DownloadManager.shared
        if manager.canDownload(contentsOf: item) {
            switch manager.containerState(for: item) {
            case .downloaded:
                Menu {
                    let counts = manager.trackCounts(forContainer: DownloadManager.containerKey(for: item))
                    Label(counts.total == 1 ? "1 song on this device" : "\(counts.total) songs on this device", systemImage: "arrow.down.circle.fill")
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        manager.removeDownload(contentsOf: item)
                        alertService.showAlertContent(with: item, subtitle: "Removed from this device", symbolName: "trash")
                    } label: {
                        Label("Remove Download", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .frame(width: 24, height: 24)
                }
                .buttonBorderShape(.circle)
                .contentShape(.rect)
                .glassButton()
                .accessibilityLabel("Downloaded")
            case let .downloading(fraction):
                Menu {
                    let counts = manager.trackCounts(forContainer: DownloadManager.containerKey(for: item))
                    Label("Downloading \(counts.downloaded) of \(counts.total)…", systemImage: "arrow.down.circle.dotted")
                    let held = manager.waitingTrackKeys(forContentsOf: item).filter { manager.cellularHeldKeys.contains($0) }
                    if !held.isEmpty {
                        Label(held.count == 1 ? "1 song waiting for Wi‑Fi" : "\(held.count) songs waiting for Wi‑Fi", systemImage: "wifi")
                        Button {
                            manager.allowCellular(forKeys: held)
                        } label: {
                            Label("Download Now Over Cellular", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                    let stopped = manager.stoppedTrackCount(forContentsOf: item)
                    if stopped > 0 {
                        Button {
                            manager.resumeDownload(contentsOf: item)
                        } label: {
                            Label(stopped == 1 ? "Retry 1 Song" : "Retry \(stopped) Songs", systemImage: "arrow.clockwise.circle")
                        }
                    }
                    Button(role: .destructive) {
                        manager.removeDownload(contentsOf: item)
                    } label: {
                        Label("Cancel Download", systemImage: "xmark.circle")
                    }
                } label: {
                    ProgressRing(fraction: fraction, lineWidth: 2.2)
                        .frame(width: 18, height: 18)
                        .frame(width: 24, height: 24)
                }
                .buttonBorderShape(.circle)
                .contentShape(.rect)
                .glassButton()
                .accessibilityLabel("Downloading, \(Int(fraction * 100)) percent")
            case nil:
                Button {
                    guard !isQueuing else { return }
                    HapticManager.shared.fireHaptic(.buttonPress)
                    guard FeatureGate.shared.unlock(.downloads) else { return }
                    isQueuing = true
                    Task { @MainActor in
                        await LocalDownloadMenuSection.download(item, alertService: alertService)
                        isQueuing = false
                    }
                } label: {
                    Group {
                        if isQueuing {
                            ProgressRing(fraction: nil, lineWidth: 2.2)
                                .frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                    }
                    .frame(width: 24, height: 24)
                }
                .buttonBorderShape(.circle)
                .contentShape(.rect)
                .glassButton()
                .accessibilityLabel("Download \(item.content.type.title)")
            }
        }
    }
}
