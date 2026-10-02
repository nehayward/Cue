import SwiftUI
import WatchSync

/// What's on the watch: Fast Download while songs are still to come, the
/// songs added one at a time, then each album, playlist and artist with
/// how far it's got and the room it takes.
struct DownloadsScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(\.zoomNamespace) private var zoom
    @State private var isShowingFastDownload = false

    var body: some View {
        let collections = store.picks.items.filter { $0.kind != .song }
        let songPicks = store.picks.items.filter { $0.kind == .song }
        List {
            Section {
                if store.remainingCount > 0 || store.fastPhase != .off {
                    Button {
                        isShowingFastDownload = true
                    } label: {
                        FastDownloadRow()
                    }
                }
                if !songPicks.isEmpty {
                    NavigationLink(value: LibraryRoute.songs) {
                        SongsRow(count: songPicks.count, bytes: store.bytesUsed(by: store.songs(in: songPicks.map(\.key))))
                    }
                    .zoomSource(LibraryRoute.songs, in: zoom)
                }
                ForEach(collections, id: \.key) { pick in
                    NavigationLink(value: LibraryRoute.pick(pick.key)) {
                        PickRow(pick: pick)
                    }
                    .zoomSource(LibraryRoute.pick(pick.key), in: zoom)
                }
                if store.picks.items.isEmpty {
                    Text("Nothing here yet. Browse your library, or choose Add to Apple Watch in Cue on your iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            } footer: {
                if !store.picks.items.isEmpty {
                    Text(storageSummary)
                }
            }
        }
        .navigationTitle("Downloads")
        .sheet(isPresented: $isShowingFastDownload) {
            FastDownloadScreen()
        }
    }

    private var storageSummary: String {
        let size = ByteCountFormatter.string(fromByteCount: store.bytesUsed, countStyle: .file)
        let songs = store.downloadedCount == 1 ? "1 song" : "\(store.downloadedCount) songs"
        return "\(songs) on this watch • \(size)"
    }
}

/// The home screen's way in: the count of songs here in the title, and
/// what's going on below it.
struct DownloadsRow: View {
    @Environment(WatchDownloadStore.self) private var store

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text("Downloads")
                    Text("\(store.downloadedCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
        }
    }

    private var detail: String {
        if store.fastPhase == .running {
            return "Fast Download • \(store.fastCompleted) of \(store.fastTotal)"
        }
        if store.remainingCount > 0 {
            return "\(store.remainingCount) to download"
        }
        if store.downloadedCount == 0 {
            return "Nothing yet"
        }
        return ByteCountFormatter.string(fromByteCount: store.bytesUsed, countStyle: .file)
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

private struct SongsRow: View {
    let count: Int
    let bytes: Int64

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note")
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading) {
                Text("Songs")
                Text("\(count == 1 ? "1 song" : "\(count) songs") • \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// An album, playlist or artist on the watch, with how far it's got.
private struct PickRow: View {
    @Environment(WatchDownloadStore.self) private var store
    let pick: WatchPick

    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(url: pick.artworkURL)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading) {
                Text(pick.title)
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
        guard let songs = store.songsByPick[pick.key] else {
            return store.unreachable.contains(pick.key) ? "Can't reach the server" : "Looking up…"
        }
        let here = songs.filter { store.isDownloaded($0.key) }.count
        if here < songs.count {
            return "\(here) of \(songs.count) downloaded"
        }
        let size = ByteCountFormatter.string(fromByteCount: store.bytesUsed(by: songs), countStyle: .file)
        let what = pick.subtitle.isEmpty ? (songs.count == 1 ? "1 song" : "\(songs.count) songs") : pick.subtitle
        return "\(what) • \(size)"
    }
}
