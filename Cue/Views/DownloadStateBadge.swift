import SonosKit
import SwiftUI

/// The small mark at the end of a row that says where a song's file is:
/// kept on this device (with a lyrics mark when its lyrics are kept too,
/// for listening offline), coming down (with how far), or still up in
/// iCloud.
/// An album, playlist or artist downloaded whole gets the same mark for
/// the set. Nothing for a song that streams and isn't being fetched. Reads
/// the download manager, the Music app's downloads for Apple songs, and,
/// for Files, the folder's iCloud status, so a row on screen follows a
/// download as it runs.
struct DownloadStateBadge: View {
    let item: PlayableContent

    private enum State: Equatable {
        case downloaded(withLyrics: Bool)
        case downloading(Double?)
        /// Paused, or failed and waiting on a retry.
        case stopped(failed: Bool)
        /// Queued, but held until Wi‑Fi (or any network) is back.
        case waiting
        case inCloud
        case none
    }

    private var state: State {
        let manager = DownloadManager.shared
        if manager.canDownload(contentsOf: item) {
            switch manager.containerState(for: item) {
            case .downloaded: return .downloaded(withLyrics: false)
            case let .downloading(fraction): return .downloading(fraction)
            case nil: return .none
            }
        }
        if manager.isDownloaded(item) {
            return .downloaded(withLyrics: DownloadLyrics.shared.withLyrics.contains(DownloadManager.key(for: item)))
        }
        if manager.waitingDownload(for: item) != nil { return .waiting }
        if manager.isDownloading(item) { return .downloading(manager.progress(for: item)) }
        if let stopped = manager.stoppedDownload(for: item) { return .stopped(failed: stopped.state == .failed) }
        if AppleDownloadsIndex.shared.isDownloaded(item) { return .downloaded(withLyrics: false) }
        if item.content.service == .files {
            switch FilesLibraryService.shared.cloudStatus(trackID: item.content.id) {
            case let .downloading(fraction): return .downloading(fraction)
            case .notDownloaded: return .inCloud
            case .local, .notCloud: return .none
            }
        }
        return .none
    }

    var body: some View {
        switch state {
        case let .downloaded(withLyrics):
            HStack(spacing: 3) {
                if withLyrics {
                    Image(systemName: "quote.bubble.fill")
                }
                Image(systemName: "arrow.down.circle.fill")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(withLyrics ? "Downloaded, with lyrics" : "Downloaded")
        case let .downloading(fraction):
            ProgressRing(fraction: fraction)
                .frame(width: 13, height: 13)
                .accessibilityLabel(fraction.map { "Downloading, \(Int($0 * 100)) percent" } ?? "Downloading")
        case let .stopped(failed):
            Image(systemName: failed ? "exclamationmark.circle" : "pause.circle")
                .font(.caption2)
                .foregroundStyle(failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .accessibilityLabel(failed ? "Download failed" : "Download paused")
        case .waiting:
            Image(systemName: "wifi")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Download waiting for Wi‑Fi")
        case .inCloud:
            Image(systemName: "icloud.and.arrow.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .none:
            EmptyView()
        }
    }
}

/// A thin ring that fills clockwise from the top. With no fraction yet
/// (queued, or iCloud not reporting), a quarter arc spins instead.
struct ProgressRing: View {
    let fraction: Double?
    var lineWidth: Double = 1.6

    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: lineWidth)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, fraction)))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: fraction)
            } else {
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 270 : -90))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
            }
        }
    }
}
