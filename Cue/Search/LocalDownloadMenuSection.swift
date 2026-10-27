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
        // A book's file downloads with its book, never as a song of its own.
        if let book = Self.book(of: item) {
            bookSection(book)
        } else if [.plex, .subsonic].contains(item.content.service) {
            if item.content.type == .track {
                if manager.isDownloaded(item) {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        manager.removeDownload(item)
                    } label: {
                        Label("Remove Download", systemImage: "trash")
                    }
                } else if let stopped = manager.stoppedDownload(for: item) {
                    // Paused or failed: say so, and offer the way back.
                    Button {
                        manager.resume(key: stopped.key)
                        Self.confirmQueued(item, alertService: alertService)
                    } label: {
                        Label(stopped.state == .failed ? "Retry Download" : "Resume Download", systemImage: "arrow.clockwise.circle")
                    }
                    if stopped.state == .failed {
                        Text(stopped.error.map { "Download failed: \($0)" } ?? "Download failed")
                    }
                    Button(role: .destructive) {
                        manager.cancel(key: stopped.key)
                    } label: {
                        Label("Cancel Download", systemImage: "xmark.circle")
                    }
                } else if let waiting = manager.waitingDownload(for: item) {
                    // Held for Wi‑Fi (or any network): say so, and let it
                    // through now when cellular is what's holding it.
                    Label(manager.network == .none ? "Waiting for a Connection" : "Waiting for Wi‑Fi", systemImage: "wifi")
                    if manager.cellularHeldKeys.contains(waiting.key) {
                        Button {
                            manager.allowCellular(forKeys: [waiting.key])
                            alertService.showAlertContent(with: item, subtitle: "Downloading over cellular", symbolName: "arrow.down.circle")
                        } label: {
                            Label("Download Now Over Cellular", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                    Button(role: .destructive) {
                        manager.cancel(key: waiting.key)
                    } label: {
                        Label("Cancel Download", systemImage: "xmark.circle")
                    }
                } else if manager.isDownloading(item) {
                    Label("Downloading…", systemImage: "arrow.down.circle.dotted")
                    Button(role: .destructive) {
                        manager.removeDownload(item)
                    } label: {
                        Label("Cancel Download", systemImage: "xmark.circle")
                    }
                } else if manager.canDownload(item) {
                    Button {
                        guard FeatureGate.shared.unlock(.downloads) else { return }
                        if manager.download(item) {
                            Self.confirmQueued(item, alertService: alertService)
                        } else {
                            Self.offerSuperForDownloads()
                        }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    freeLimitNote
                }
            } else if manager.canDownload(contentsOf: item) {
                switch manager.containerState(for: item) {
                case .downloaded:
                    let removed = manager.removedTrackCount(forContentsOf: item)
                    if removed > 0 {
                        Button {
                            downloadContainer()
                        } label: {
                            Label(removed == 1 ? "Download 1 Removed Song" : "Download \(removed) Removed Songs", systemImage: "arrow.down.circle")
                        }
                    }
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        manager.removeDownload(contentsOf: item)
                        alertService.showAlertContent(with: item, subtitle: "Removed from this device", symbolName: "trash")
                    } label: {
                        Label("Remove Download", systemImage: "trash")
                    }
                case .downloading:
                    let stopped = manager.stoppedTrackCount(forContentsOf: item)
                    let held = manager.waitingTrackKeys(forContentsOf: item).filter { manager.cellularHeldKeys.contains($0) }
                    if !held.isEmpty {
                        Label(held.count == 1 ? "1 song waiting for Wi‑Fi" : "\(held.count) songs waiting for Wi‑Fi", systemImage: "wifi")
                        Button {
                            manager.allowCellular(forKeys: held)
                        } label: {
                            Label("Download Now Over Cellular", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                    if stopped > 0 {
                        Button {
                            manager.resumeDownload(contentsOf: item)
                        } label: {
                            Label(stopped == 1 ? "Retry 1 Song" : "Retry \(stopped) Songs", systemImage: "arrow.clockwise.circle")
                        }
                    } else {
                        Label("Downloading…", systemImage: "arrow.down.circle.dotted")
                    }
                    Button(role: .destructive) {
                        manager.removeDownload(contentsOf: item)
                    } label: {
                        Label("Cancel Download", systemImage: "xmark.circle")
                    }
                case nil:
                    Button {
                        downloadContainer()
                    } label: {
                        Label("Download \(item.content.type.title)", systemImage: "arrow.down.circle")
                    }
                    freeLimitNote
                }
            }
        } else if item.content.service == .files {
            filesCloudSection
        } else if AppleDownloadsIndex.shared.isDownloaded(item) {
            Label("Downloaded in Music", systemImage: "arrow.down.circle.fill")
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
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
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
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
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
            Text("\(manager.heldAgainstLimit) of \(DownloadManager.freeSongLimit) free downloads")
        }
    }

    private func downloadContainer() {
        guard FeatureGate.shared.unlock(.download(of: item)) else { return }
        Task { @MainActor in
            await Self.download(item, alertService: alertService)
        }
    }

    /// The loaded book `item` is a file of, if it is one.
    private static func book(of item: PlayableContent) -> PlayableContent? {
        let books = AudiobookPlayer.shared
        return books.contains(item) ? books.current?.book : nil
    }

    /// The whole book, as its page's download button has it.
    @ViewBuilder
    private func bookSection(_ book: PlayableContent) -> some View {
        let manager = DownloadManager.shared
        if manager.canDownload(contentsOf: book) {
            // At a glance, not the progress: an open menu redrawn with every
            // bit of progress flickers.
            switch manager.containerPresence(for: book) {
            case .downloaded:
                Label(book.isPodcastEpisode ? "Episode Downloaded" : "Book Downloaded", systemImage: "arrow.down.circle.fill")
            case .downloading:
                Label(book.isPodcastEpisode ? "Downloading Episode…" : "Downloading Book…", systemImage: "arrow.down.circle.dotted")
            case nil:
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    guard FeatureGate.shared.unlock(.bookDownloads) else { return }
                    Task { @MainActor in
                        await Self.download(book, alertService: alertService)
                    }
                } label: {
                    Label(book.isPodcastEpisode ? "Download Episode" : "Download Book", systemImage: "arrow.down.circle")
                }
            }
        }
    }

    /// The banner for a song just queued or resumed — unless it's waiting
    /// for Wi‑Fi, when the cellular question says so instead.
    @MainActor
    static func confirmQueued(_ item: PlayableContent, alertService: AlertService) {
        let manager = DownloadManager.shared
        if let waiting = manager.waitingDownload(for: item) {
            if !manager.cellularHeldKeys.contains(waiting.key) {
                alertService.showAlertContent(with: item, subtitle: "Waiting for a connection", symbolName: "wifi.slash")
            }
            return
        }
        alertService.showAlertContent(with: item, subtitle: "Downloading", symbolName: "arrow.down.circle")
    }

    /// Queues a whole album, playlist or artist and says what happened.
    /// Shared with the detail screen's header button; callers check the
    /// feature gate first, so the paywall comes up on the tap itself.
    @MainActor
    static func download(_ item: PlayableContent, alertService: AlertService) async {
        let manager = DownloadManager.shared
        let result = await manager.download(contentsOf: item)
        guard !result.couldNotLoad else {
            let server = item.content.service == .plex ? "Plex" : item.content.service == .audiobookshelf ? "Audiobookshelf" : "the server"
            alertService.showAlertContent(with: item, subtitle: "Couldn't reach \(server). Try again.", symbolName: "exclamationmark.triangle")
            return
        }
        switch (result.queued, result.heldBack) {
        case (0, 0):
            if manager.isDownloaded(contentsOf: item) {
                alertService.showAlertContent(with: item, subtitle: "Already on this device", symbolName: "arrow.down.circle.fill")
            } else {
                alertService.showAlert(with: "Nothing to download", imageName: "arrow.down.circle")
            }
        case (0, _) where item.content.type == .audiobook:
            FeatureGate.shared.presentPaywall(PaywallReason(feature: .bookDownloads))
        case (0, _):
            offerSuperForDownloads()
        case (let queued, 0):
            // Held for Wi‑Fi, the cellular question speaks for the batch.
            let held = Set(manager.cellularHeldKeys)
            guard !manager.waitingTrackKeys(forContentsOf: item).contains(where: held.contains) else { return }
            let what = item.content.type == .audiobook ? "Downloading" : (queued == 1 ? "Downloading 1 song" : "Downloading \(queued) songs")
            alertService.showAlertContent(with: item, subtitle: LocalizedStringKey(what), symbolName: "arrow.down.circle")
        case (let queued, let heldBack):
            // Part of the album made it in before the limit; say how much
            // didn't, and what would take the rest.
            offerSuperForDownloads(detail: "\(queued) of \(queued + heldBack) songs are downloading. Cue Super makes room for the other \(heldBack), and every song after.")
        }
    }

    /// The free download limit was reached: the paywall comes up on the
    /// tap that hit it, opening on the free meter (`PaywallReasonCard`), so
    /// it's plain why and how many are held.
    @MainActor
    static func offerSuperForDownloads(detail: String? = nil) {
        FeatureGate.shared.presentPaywall(PaywallReason(feature: .unlimitedDownloads, detail: detail))
    }
}
