import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI

/// The download manager: what's coming down, what's kept on this device,
/// and — for a Files folder in iCloud Drive — how much of it is here.
/// Reached from Settings › Storage.
struct DownloadsScreen: View {
    @Environment(Router.self) private var router: Router?
    @State private var manager = DownloadManager.shared
    @State private var cache = PlaybackCache.shared
    @State private var files = FilesLibraryService.shared
    @State private var cloudSummary: (local: Int, remote: Int)?

    var body: some View {
        @Bindable var manager = manager
        @Bindable var cache = cache

        List {
            Section {
                Picker("Keep Recent Songs", selection: $cache.songLimit) {
                    Text("Off").tag(0)
                    Text("25 songs").tag(25)
                    Text("50 songs").tag(50)
                    Text("100 songs").tag(100)
                    Text("250 songs").tag(250)
                    Text("500 songs").tag(500)
                }
                if cache.isEnabled {
                    Picker("Fetch Ahead", selection: $cache.prefetchCount) {
                        Text("Next song").tag(1)
                        Text("Next 3 songs").tag(3)
                        Text("Next 5 songs").tag(5)
                        Text("Next 10 songs").tag(10)
                    }
                    Toggle(isOn: $cache.allowsCellular) {
                        Label("Fill Over Cellular", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    LabeledContent("Cached", value: cache.entries.isEmpty
                        ? "Nothing yet"
                        : "\(cache.entries.count == 1 ? "1 song" : "\(cache.entries.count) songs") • \(ByteCountFormatter.string(fromByteCount: cache.totalBytes, countStyle: .file))")
                    if !cache.inFlight.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(cache.inFlight.count == 1 ? "Fetching 1 song ahead…" : "Fetching \(cache.inFlight.count) songs ahead…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !cache.entries.isEmpty {
                        Button(role: .destructive) {
                            cache.clear()
                        } label: {
                            Label("Clear Cache", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("Playback Cache")
            } footer: {
                Text("Songs coming up in the on-device queue are fetched before they play, and recent ones kept, so playback holds through a tunnel or a dead spot. The least recently played goes first when the cap is reached. Covers Plex and Subsonic; upcoming iCloud Drive songs are asked to download ahead too. Downloads you choose yourself are kept separately.")
            }

            if let remaining = manager.remainingFreeSlots {
                freeLimitSection(remaining: remaining)
            }

            if !manager.active.isEmpty {
                Section {
                    ForEach(manager.active) { item in
                        activeRow(item)
                    }
                } header: {
                    Text("Downloading")
                } footer: {
                    Text("Downloads carry on when Cue is in the background, with their progress on the Lock Screen, and pick up where they left off after a relaunch.")
                }
            }

            if files.isConfigured, files.isCloudFolder {
                cloudSection
            }

            Section {
                Toggle(isOn: $manager.allowsCellular) {
                    Label("Use Cellular Data", systemImage: "antenna.radiowaves.left.and.right")
                }
            } footer: {
                Text("Applies to downloads queued from now on. iCloud Drive follows the Files setting in iOS Settings.")
            }

            if !manager.completed.isEmpty {
                Section {
                    ForEach(manager.completed) { item in
                        completedRow(item)
                    }
                    .onDelete { offsets in
                        let completed = manager.completed
                        for index in offsets where completed.indices.contains(index) {
                            manager.remove(key: completed[index].key)
                        }
                    }
                    Button(role: .destructive) {
                        manager.removeAllCompleted()
                    } label: {
                        Text("Remove All Downloads")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .listRowBackground(Color.clear)
                } header: {
                    Text("On This Device")
                } footer: {
                    Text("\(manager.completed.count == 1 ? "1 song" : "\(manager.completed.count) songs") • \(ByteCountFormatter.string(fromByteCount: manager.completedBytes, countStyle: .file)). Kept until you remove them; not included in backups.")
                }
            } else if manager.active.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Downloads", systemImage: "arrow.down.circle")
                    } description: {
                        Text(manager.remainingFreeSlots == nil
                             ? "Download a Plex or Subsonic song or album from its menu to keep it on this device."
                             : "Download a Plex or Subsonic song or album from its menu to keep it on this device. Up to \(DownloadManager.freeSongLimit) songs are free.")
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !manager.active.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            manager.pauseAll()
                        } label: {
                            Label("Pause All", systemImage: "pause.circle")
                        }
                        Button {
                            manager.resumeAll()
                        } label: {
                            Label("Resume All", systemImage: "play.circle")
                        }
                        Divider()
                        Button(role: .destructive) {
                            manager.active.forEach { manager.cancel(key: $0.key) }
                        } label: {
                            Label("Cancel All", systemImage: "xmark.circle")
                        }
                    } label: {
                        Label("Downloads", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            files.startCloudMonitor()
            await refreshCloudSummary()
        }
        .onDisappear {
            files.stopCloudMonitor()
        }
        .onChange(of: files.cloudProgress.isEmpty) {
            Task { await refreshCloudSummary() }
        }
    }

    // MARK: - Free limit

    /// How much of the free allowance is used, and the way past it. The
    /// upgrade card appears once the meter is mostly full — early enough to
    /// read as "here's what's coming", not as a wall.
    private func freeLimitSection(remaining: Int) -> some View {
        let limit = DownloadManager.freeSongLimit
        let held = manager.heldCount
        return Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Free Downloads", systemImage: "arrow.down.circle")
                    Spacer()
                    Text("\(held) of \(limit) songs")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ProgressView(value: Double(held), total: Double(limit))
                    .progressViewStyle(.linear)
                    .tint(remaining == 0 ? .red : .accentColor)
            }
            if remaining <= limit / 5 {
                PaywallButtonView()
                    .environment(router)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        } footer: {
            Text(remaining == 0
                 ? "Every free slot is taken. Remove a download to free one, or get Cue Super for unlimited downloads."
                 : "Songs on this device and on their way count; removing one frees its slot. Cue Super removes the limit.")
        }
    }

    // MARK: - Rows

    private func activeRow(_ item: DownloadManager.Item) -> some View {
        HStack(spacing: 12) {
            artwork(item.artwork)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: item.state == .queued ? 0 : item.progress)
                    .progressViewStyle(.linear)
                    .tint(item.state == .failed ? .red : .accentColor)
                Text(statusText(item))
                    .font(.caption2)
                    .foregroundStyle(item.state == .failed ? .red : .secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            Button {
                switch item.state {
                case .queued, .downloading: manager.pause(key: item.key)
                case .paused, .failed: manager.resume(key: item.key)
                case .completed: break
                }
            } label: {
                Image(systemName: item.isActive ? "pause.circle.fill" : "arrow.clockwise.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                manager.cancel(key: item.key)
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
        }
    }

    private func completedRow(_ item: DownloadManager.Item) -> some View {
        HStack(spacing: 12) {
            artwork(item.artwork)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                item.service.image
                    .frame(width: 14, height: 14)
                Text(ByteCountFormatter.string(fromByteCount: item.fileSize ?? 0, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusText(_ item: DownloadManager.Item) -> String {
        switch item.state {
        case .queued:
            return "Waiting…"
        case .downloading:
            guard item.bytesExpected > 0 else { return "Starting…" }
            let received = ByteCountFormatter.string(fromByteCount: item.bytesReceived, countStyle: .file)
            let expected = ByteCountFormatter.string(fromByteCount: item.bytesExpected, countStyle: .file)
            return "\(received) of \(expected)"
        case .paused:
            return "Paused"
        case .failed:
            return item.error ?? "Failed"
        case .completed:
            return "Done"
        }
    }

    @ViewBuilder
    private func artwork(_ url: URL?) -> some View {
        LazyImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - iCloud Drive

    private var cloudSection: some View {
        Section {
            if let cloudSummary {
                LabeledContent("On This Device", value: "\(cloudSummary.local.formatted()) of \((cloudSummary.local + cloudSummary.remote).formatted()) songs")
            } else {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Checking the folder…")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(files.cloudProgress.keys.sorted(), id: \.self) { path in
                let song = files.song(atRelativePath: path)
                HStack(spacing: 12) {
                    artwork(song?.thumbnail)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song?.title ?? (path as NSString).lastPathComponent)
                            .lineLimit(1)
                        ProgressView(value: files.cloudProgress[path] ?? 0)
                            .progressViewStyle(.linear)
                    }
                }
            }

            if let cloudSummary, cloudSummary.remote > 0 {
                Button {
                    let ids = files.downloadAllFromCloud()
                    ContinuedDownloadTask.shared.track(cloudTrackIDs: ids, title: "Downloading \(files.folderName ?? "your music")")
                } label: {
                    Label("Download Everything", systemImage: "icloud.and.arrow.down")
                }
            }
            if let cloudSummary, cloudSummary.local > 0 {
                Button(role: .destructive) {
                    files.removeAllFromDevice()
                    Task { await refreshCloudSummary() }
                } label: {
                    Label("Remove Downloads from This Device", systemImage: "icloud.slash")
                }
            }
        } header: {
            Text(files.folderName.map { "iCloud Drive • \($0)" } ?? "iCloud Drive")
        } footer: {
            Text("iCloud downloads are carried by the system, so they finish even when Cue is closed. Removed songs stay in iCloud and download again when played.")
        }
    }

    private func refreshCloudSummary() async {
        guard files.isConfigured, files.isCloudFolder else {
            cloudSummary = nil
            return
        }
        cloudSummary = files.cloudSummary()
    }
}

#Preview {
    NavigationStack {
        DownloadsScreen()
    }
    .withEnvironments()
}
