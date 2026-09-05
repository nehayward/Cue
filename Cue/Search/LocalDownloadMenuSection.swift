import Analytics
import SonosKit
import SwiftUI

/// Download state and actions for playing on this device — the rows inside
/// a track's "This Device" submenu and the local player's own menu. Plex and
/// Subsonic tracks download into our own storage through the download
/// manager; a Files track in iCloud Drive is fetched or evicted in place;
/// Apple tracks can only be badged (the Music app owns those downloads —
/// see `AppleDownloadsIndex`).
struct LocalDownloadMenuSection: View {
    @Environment(AlertService.self) private var alertService: AlertService

    let item: PlayableContent

    var body: some View {
        let manager = DownloadManager.shared
        if [.plex, .subsonic].contains(item.content.service) {
            if item.content.type == .track {
                if manager.isDownloaded(item) {
                    Button(role: .destructive) {
                        manager.removeDownload(item)
                    } label: {
                        Label("Remove Download", systemImage: "trash")
                    }
                } else if manager.isDownloading(item) {
                    Label("Downloading…", systemImage: "arrow.down.circle.dotted")
                } else if manager.canDownload(item) {
                    Button {
                        guard FeatureGate.shared.unlock(.downloads) else { return }
                        if manager.download(item) {
                            alertService.showAlertContent(with: item, subtitle: "Downloading", symbolName: "arrow.down.circle")
                        } else {
                            offerSuperForDownloads()
                        }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    freeLimitNote
                }
            } else if [.album, .playlist, .artist].contains(item.content.type) {
                Button {
                    downloadContainer()
                } label: {
                    Label("Download \(item.content.type.title)", systemImage: "arrow.down.circle")
                }
                freeLimitNote
            }
        } else if item.content.service == .files {
            filesCloudSection
        } else if AppleDownloadsIndex.shared.isDownloaded(item) {
            Label("Downloaded", systemImage: "arrow.down.circle.fill")
        }
    }

    /// iCloud Drive keeps files in the cloud until asked; these ask, or
    /// hand the space back. Nothing shows for a folder on the device itself.
    @ViewBuilder
    private var filesCloudSection: some View {
        let files = FilesLibraryService.shared
        if files.isCloudFolder {
            if item.content.type == .track {
                switch files.cloudStatus(trackID: item.content.id) {
                case .notDownloaded:
                    Button {
                        guard FeatureGate.shared.unlock(.downloads) else { return }
                        files.downloadFromCloud(trackIDs: [item.content.id])
                        ContinuedDownloadTask.shared.track(cloudTrackIDs: [item.content.id], title: "Downloading \(item.title)")
                        alertService.showAlertContent(with: item, subtitle: "Downloading from iCloud", symbolName: "icloud.and.arrow.down")
                    } label: {
                        Label("Download from iCloud", systemImage: "icloud.and.arrow.down")
                    }
                case .downloading:
                    Label("Downloading from iCloud…", systemImage: "icloud.and.arrow.down")
                case .local:
                    Button(role: .destructive) {
                        files.removeFromDevice(trackIDs: [item.content.id])
                    } label: {
                        Label("Remove Download", systemImage: "icloud.slash")
                    }
                case .notCloud:
                    EmptyView()
                }
            } else if [.album, .playlist, .artist].contains(item.content.type) {
                Button {
                    cloudContainer(download: true)
                } label: {
                    Label("Download from iCloud", systemImage: "icloud.and.arrow.down")
                }
                Button(role: .destructive) {
                    cloudContainer(download: false)
                } label: {
                    Label("Remove Downloads", systemImage: "icloud.slash")
                }
            }
        }
    }

    private func cloudContainer(download: Bool) {
        Task { @MainActor in
            let ids = await LocalPlaybackService.shared.containerTracks(for: item).map(\.content.id)
            guard !ids.isEmpty else { return }
            if download {
                FilesLibraryService.shared.downloadFromCloud(trackIDs: ids)
                ContinuedDownloadTask.shared.track(cloudTrackIDs: ids, title: "Downloading \(item.title)")
                alertService.showAlertContent(with: item, subtitle: "Downloading \(ids.count) songs from iCloud", symbolName: "icloud.and.arrow.down")
            } else {
                FilesLibraryService.shared.removeFromDevice(trackIDs: ids)
                alertService.showAlertContent(with: item, subtitle: "Removed from this device", symbolName: "icloud.slash")
            }
        }
    }

    /// Where the free limit stands, as a plain line under the download
    /// action. Gone with Super, which has no limit to report.
    @ViewBuilder
    private var freeLimitNote: some View {
        let manager = DownloadManager.shared
        if manager.remainingFreeSlots != nil {
            Text("\(manager.heldCount) of \(DownloadManager.freeSongLimit) free downloads")
        }
    }

    private func downloadContainer() {
        guard FeatureGate.shared.unlock(.downloads) else { return }
        Task { @MainActor in
            let result = await DownloadManager.shared.download(contentsOf: item)
            switch (result.queued, result.heldBack) {
            case (0, 0):
                alertService.showAlert(with: "Nothing left to download", imageName: "arrow.down.circle")
            case (0, _):
                offerSuperForDownloads()
            case (let queued, 0):
                alertService.showAlertContent(with: item, subtitle: queued == 1 ? "Downloading 1 song" : "Downloading \(queued) songs", symbolName: "arrow.down.circle")
            case (let queued, let heldBack):
                // Part of the album made it in before the limit; say how much
                // didn't, and where the rest is.
                offerSuperForDownloads(text: "Downloading \(queued) of \(queued + heldBack) songs")
            }
        }
    }

    /// The free download limit was reached. Says so in a banner that opens
    /// the paywall when tapped, so the menu's own tap isn't hijacked by a
    /// full-screen cover.
    private func offerSuperForDownloads(text: String = "\(DownloadManager.freeSongLimit) free downloads used") {
        Analytics.shared.track(.downloadLimitReached)
        alertService.showActionAlert(with: text, subtitle: "Tap for unlimited with Cue Super", imageName: "arrow.down.circle") {
            HapticManager.shared.fireHaptic(.buttonPress)
            Analytics.shared.track(.viewedPaywall, with: ["source": "downloads"])
            Router.main.fullScreenCover(to: .paywall)
        }
    }
}
