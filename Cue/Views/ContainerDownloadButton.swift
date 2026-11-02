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
                    Label("\(item.content.type.downloadCount(counts.total)) on this device", systemImage: "arrow.down.circle.fill")
                    let removed = manager.removedTrackCount(forContentsOf: item)
                    if removed > 0 {
                        Button {
                            downloadWhole()
                        } label: {
                            Label(removed == 1 ? "Download 1 More Song" : "Download \(removed) More Songs", systemImage: "arrow.down.circle")
                        }
                    }
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
                    Label("Downloading \(counts.downloaded) of \(item.content.type.downloadCount(counts.total))…", systemImage: "arrow.down.circle.dotted")
                    let held = manager.waitingTrackKeys(forContentsOf: item).filter { manager.cellularHeldKeys.contains($0) }
                    if !held.isEmpty {
                        Label("\(item.content.type.downloadCount(held.count)) waiting for Wi‑Fi", systemImage: "wifi")
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
                            Label("Retry \(item.content.type.downloadCount(stopped).capitalized)", systemImage: "arrow.clockwise.circle")
                        }
                    }
                    // Taken out on the way (cancelled, or gone from disk): a
                    // book isn't whole without them.
                    let removed = manager.removedTrackCount(forContentsOf: item)
                    if removed > 0 {
                        Button {
                            downloadWhole()
                        } label: {
                            Label("Download \(item.content.type.downloadCount(removed).capitalized) Again", systemImage: "arrow.down.circle")
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
                    downloadWhole()
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

    /// Queues the whole thing — or, for one trimmed, the songs taken out.
    private func downloadWhole() {
        guard !isQueuing else { return }
        HapticManager.shared.fireHaptic(.buttonPress)
        guard FeatureGate.shared.unlock(.download(of: item)) else { return }
        isQueuing = true
        Task { @MainActor in
            await LocalDownloadMenuSection.download(item, alertService: alertService)
            isQueuing = false
        }
    }
}

/// The same button on an album or playlist page of the on-device library
/// (`OnDeviceLibrary`), which is all here: a filled arrow, with how many
/// songs and Remove Download behind it. The page goes back once its songs
/// are gone (`MediaDetailView.loadOnDeviceTracks`). Not for what only the
/// Music app can remove.
struct OnDeviceDownloadButton: View {
    @Environment(AlertService.self) private var alertService

    let container: PlayableContent

    var body: some View {
        let removable = OnDeviceLibrary.removableCount(of: container)
        if removable > 0 {
            Menu {
                Label("\(ContentType.track.downloadCount(removable)) on this device", systemImage: "arrow.down.circle.fill")
                Button(role: .destructive) {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    OnDeviceLibrary.removeDownloads(of: container)
                    alertService.showAlertContent(with: container, subtitle: "Removed from this device", symbolName: "trash")
                } label: {
                    Label("Remove Download", systemImage: "trash")
                }
                // The icon too: a menu tints it with the app's colour.
                .tint(.red)
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonBorderShape(.circle)
            .contentShape(.rect)
            .glassButton()
            .accessibilityLabel("Downloaded")
        }
    }
}

/// Remove Download for an album, artist or playlist row of the on-device
/// library, as a swipe and in its long-press menu: the list's own way to
/// take one off this device without opening it.
struct OnDeviceRemoveActions: ViewModifier {
    @Environment(AlertService.self) private var alertService

    let container: PlayableContent

    func body(content: Content) -> some View {
        if OnDeviceLibrary.removableCount(of: container) > 0 {
            content
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive, action: remove) {
                        Label("Remove", systemImage: "trash")
                    }
                    // Red, as a delete is: the app's tint wins otherwise.
                    .tint(.red)
                }
                .contextMenu {
                    Button(role: .destructive, action: remove) {
                        Label("Remove Download", systemImage: "trash")
                    }
                    // The icon too: a menu tints it with the app's colour.
                    .tint(.red)
                }
        } else {
            content
        }
    }

    private func remove() {
        HapticManager.shared.fireHaptic(.buttonPress)
        OnDeviceLibrary.removeDownloads(of: container)
        alertService.showAlertContent(with: container, subtitle: "Removed from this device", symbolName: "trash")
    }
}

extension View {
    /// Remove Download on a row of the on-device library: see
    /// `OnDeviceRemoveActions`.
    func onDeviceRemoveActions(for container: PlayableContent) -> some View {
        modifier(OnDeviceRemoveActions(container: container))
    }
}

extension ContentType {
    /// How many things a download of this holds, by name: a book's files,
    /// anything else's songs.
    func downloadCount(_ count: Int) -> String {
        let noun = self == .audiobook ? "file" : "song"
        return count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }
}
