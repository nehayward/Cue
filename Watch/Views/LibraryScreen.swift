import SwiftUI
import WatchKit
import WatchSync

/// The watch's home: what's playing, Fast Download while songs are still to
/// come, the albums, playlists and artists on the watch, and Add Music to
/// browse the iPhone's libraries for more.
struct LibraryScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchPlayer.self) private var player
    @State private var isShowingFastDownload = false

    var body: some View {
        NavigationStack {
            List {
                if let track = player.current {
                    NavigationLink {
                        NowPlayingView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(track.title)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                }

                if store.remainingCount > 0 || store.fastPhase != .off {
                    Button {
                        isShowingFastDownload = true
                    } label: {
                        FastDownloadRow()
                    }
                }

                NavigationLink(value: WatchBrowsePath.root) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Add Music")
                            Text("Browse Plex and Subsonic on your iPhone")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }

                if store.library.isEmpty {
                    emptyState
                } else {
                    Section {
                        ForEach(store.library.collections) { collection in
                            NavigationLink(value: collection.key) {
                                CollectionRow(collection: collection)
                            }
                        }
                    } footer: {
                        Text(storageSummary)
                    }
                }
            }
            .navigationTitle("Cue")
            .navigationDestination(for: String.self) { key in
                CollectionScreen(collectionKey: key)
            }
            .navigationDestination(for: WatchBrowsePath.self) { path in
                BrowseScreen(path: path)
            }
            .navigationDestination(for: WatchBrowseItem.self) { item in
                BrowseItemScreen(item: item)
            }
            .sheet(isPresented: $isShowingFastDownload) {
                FastDownloadScreen()
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "music.note.list")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("No Music Yet")
                .font(.headline)
            Text("Tap Add Music, or in Cue on your iPhone choose Add to Apple Watch from an album or playlist's menu.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(Color.clear)
    }

    private var storageSummary: String {
        let size = ByteCountFormatter.string(fromByteCount: store.bytesUsed, countStyle: .file)
        let songs = store.downloadedCount == 1 ? "1 song" : "\(store.downloadedCount) songs"
        return "\(songs) on this watch • \(size)"
    }
}

/// The way into Fast Download, saying what it would do or is doing.
private struct FastDownloadRow: View {
    @Environment(WatchDownloadStore.self) private var store

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text("Fast Download")
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: "bolt.horizontal.circle.fill")
                .foregroundStyle(.tint)
        }
    }

    private var detail: String {
        switch store.fastPhase {
        case .running:
            let speed = store.bytesPerSecond.map { FastDownloadScreen.speedText($0) }
            return ["\(store.fastCompleted) of \(store.fastTotal)", speed].compactMap { $0 }.joined(separator: " • ")
        case .finished:
            return store.failedCount > 0 ? "\(store.failedCount) couldn't download" : "Done"
        case .off:
            let count = store.remainingCount
            return count == 1 ? "1 song to download" : "\(count) songs to download"
        }
    }
}

private struct CollectionRow: View {
    @Environment(WatchDownloadStore.self) private var store
    let collection: WatchCollection

    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(url: collection.artworkURL)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading) {
                Text(collection.title)
                    .lineLimit(1)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
    }

    private var detail: String {
        let total = collection.trackKeys.count
        let here = store.downloadedCount(in: collection)
        if here < total {
            return "\(here) of \(total) downloaded"
        }
        return collection.subtitle.isEmpty ? (total == 1 ? "1 song" : "\(total) songs") : collection.subtitle
    }
}
