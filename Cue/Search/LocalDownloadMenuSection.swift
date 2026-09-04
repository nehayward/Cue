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
                        manager.download(item)
                        alertService.showAlertContent(with: item, subtitle: "Downloading", symbolName: "arrow.down.circle")
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
            } else if [.album, .playlist, .artist].contains(item.content.type) {
                Button {
                    downloadContainer()
                } label: {
                    Label("Download \(item.content.type.title)", systemImage: "arrow.down.circle")
                }
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

    private func downloadContainer() {
        Task { @MainActor in
            let count = await DownloadManager.shared.download(contentsOf: item)
            guard count > 0 else {
                alertService.showAlert(with: "Nothing left to download", imageName: "arrow.down.circle")
                return
            }
            alertService.showAlertContent(with: item, subtitle: count == 1 ? "Downloading 1 song" : "Downloading \(count) songs", symbolName: "arrow.down.circle")
        }
    }
}
