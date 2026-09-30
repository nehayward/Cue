import SonosKit
import SwiftUI

/// The small mark at the end of a row that says where a song's file is:
/// kept on this device, coming down (with how far), or still up in iCloud.
/// An album, playlist or artist downloaded whole gets the same mark for
/// the set. Nothing for a song that streams and isn't being fetched. Reads
/// the download manager and, for Files, the folder's iCloud status, so a
/// row on screen follows a download as it runs.
struct DownloadStateBadge: View {
    let item: PlayableContent

    private enum State: Equatable {
        case downloaded
        case downloading(Double?)
        /// Paused, or failed and waiting on a retry.
        case stopped(failed: Bool)
        case inCloud
        case none
    }

    private var state: State {
        let manager = DownloadManager.shared
        if manager.canDownload(contentsOf: item) {
            switch manager.containerState(for: item) {
            case .downloaded: return .downloaded
            case let .downloading(fraction): return .downloading(fraction)
            case nil: return .none
            }
        }
        if manager.isDownloaded(item) { return .downloaded }
        if manager.isDownloading(item) { return .downloading(manager.progress(for: item)) }
        if let stopped = manager.stoppedDownload(for: item) { return .stopped(failed: stopped.state == .failed) }
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
        case .downloaded:
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case let .downloading(fraction):
            ProgressRing(fraction: fraction)
                .frame(width: 13, height: 13)
                .accessibilityLabel(fraction.map { "Downloading, \(Int($0 * 100)) percent" } ?? "Downloading")
        case let .stopped(failed):
            Image(systemName: failed ? "exclamationmark.circle" : "pause.circle")
                .font(.caption2)
                .foregroundStyle(failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .accessibilityLabel(failed ? "Download failed" : "Download paused")
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
