import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI

/// The download manager: what's coming down, what's kept on this device,
/// and — for a Files folder in iCloud Drive — how much of it is here.
/// Reached from Settings › Storage.
struct DownloadsScreen: View {
    @State private var manager = DownloadManager.shared
    @State private var files = FilesLibraryService.shared
    @State private var cloudSummary: (local: Int, remote: Int)?

    var body: some View {
        @Bindable var manager = manager

        List {
            if !manager.active.isEmpty {
                Section {
                    ForEach(manager.active) { item in
                        activeRow(item)
                    }
                } header: {
                    Text("Downloading")
                } footer: {
                    Text("Downloads carry on when Cue is in the background, and pick up where they left off after a relaunch.")
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
                        Text("Download a Plex or Subsonic song or album from its menu to keep it on this device.")
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
                    files.downloadAllFromCloud()
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
