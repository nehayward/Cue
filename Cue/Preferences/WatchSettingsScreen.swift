import NukeUI
import SwiftUI
import WatchSync

/// What's on the Apple Watch: the albums, playlists and artists put there
/// from their menus, how much of each has come down by the watch's last
/// report, and how to make the watch download faster. Reached from
/// Settings › Storage when a watch is paired.
struct WatchSettingsScreen: View {
    @State private var watch = WatchSyncService.shared
    @State private var isConfirmingRemoveAll = false

    var body: some View {
        List {
            if !watch.isWatchAppInstalled {
                Section {
                    ContentUnavailableView(
                        "Cue Isn't on Your Watch",
                        systemImage: "applewatch",
                        description: Text("Open the Watch app on this iPhone and install Cue under Available Apps.")
                    )
                }
            } else if watch.library.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Nothing on Your Watch",
                        systemImage: "applewatch",
                        description: Text("Open a Plex or Subsonic album or playlist, then choose Add to Apple Watch from its menu. Your watch downloads it and plays it without your iPhone.")
                    )
                }
            } else {
                collectionsSection
            }

            fastDownloadSection

            if !watch.library.isEmpty {
                Section {
                    Button(role: .destructive) {
                        isConfirmingRemoveAll = true
                    } label: {
                        Label("Remove All from Apple Watch", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove everything from Apple Watch?", isPresented: $isConfirmingRemoveAll, titleVisibility: .visible) {
            Button("Remove All", role: .destructive) {
                watch.removeAll()
            }
        } message: {
            Text("The songs are deleted from your watch. They stay on your server and can be added again.")
        }
    }

    private var collectionsSection: some View {
        Section {
            ForEach(watch.library.collections) { collection in
                row(collection)
                    .swipeActions {
                        Button(role: .destructive) {
                            watch.removeCollection(key: collection.key)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
            }
        } header: {
            Text("On Apple Watch")
        } footer: {
            Text(summary)
        }
    }

    private var summary: String {
        let songs = watch.songCount == 1 ? "1 song" : "\(watch.songCount) songs"
        guard let status = watch.status, status.libraryRevision == watch.library.revision else {
            return "\(songs). Waiting for your watch to pick up the latest changes."
        }
        var parts = ["\(status.downloadedCount) of \(songs) downloaded", ByteCountFormatter.string(fromByteCount: status.bytesUsed, countStyle: .file)]
        if status.failedCount > 0 {
            parts.append(status.failedCount == 1 ? "1 failed" : "\(status.failedCount) failed")
        }
        return parts.joined(separator: " • ") + ". Swipe to remove."
    }

    private func row(_ collection: WatchCollection) -> some View {
        let total = collection.trackKeys.count
        let downloaded = watch.downloadedCount(of: collection)
        return HStack(spacing: 12) {
            LazyImage(url: collection.artworkURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .lineLimit(1)
                Text([kindTitle(collection.kind), collection.subtitle].filter { !$0.isEmpty }.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if downloaded < total {
                    ProgressView(value: Double(downloaded), total: Double(max(total, 1)))
                        .progressViewStyle(.linear)
                }
            }
            Spacer(minLength: 0)
            Text(downloaded == total ? (total == 1 ? "1 song" : "\(total) songs") : "\(downloaded) of \(total)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func kindTitle(_ kind: WatchCollection.Kind) -> String {
        switch kind {
        case .album: "Album"
        case .playlist: "Playlist"
        case .artist: "Artist"
        case .songs: "Songs"
        }
    }

    private var fastDownloadSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fast Download")
                    Text("Open Cue on your watch and tap Fast Download, then turn off Bluetooth on this iPhone in Settings › Bluetooth.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .foregroundStyle(.tint)
            }
        } footer: {
            Text("While your iPhone is connected over Bluetooth, your watch downloads through it, a song at a time. With Bluetooth off, the watch uses its own Wi‑Fi and is many times faster. Control Center's Bluetooth button leaves your watch connected, so use Settings. Headphones stay connected to your watch. Turn Bluetooth back on when the watch says it's done.")
        }
    }
}
