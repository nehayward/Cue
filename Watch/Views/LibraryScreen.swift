import SwiftUI
import WatchKit
import WatchSync

/// Where a library row goes: one pick's songs, or the songs added one at
/// a time.
enum LibraryRoute: Hashable {
    case pick(String)
    case songs
}

/// The watch's home: what's playing, Fast Download while songs are still to
/// come, Add Music to browse the servers, and the albums, playlists and
/// artists on the watch — with the songs added on their own gathered in one
/// row. The first time there's music to fetch, it asks at what quality.
struct LibraryScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchPlayer.self) private var player
    @State private var sheet: Sheet?
    @State private var hasAskedQuality = false

    private enum Sheet: String, Identifiable {
        case fastDownload, quality
        var id: String { rawValue }
    }

    private var needsQuality: Bool {
        !store.hasChosenQuality && !store.picks.items.isEmpty
    }

    var body: some View {
        let collections = store.picks.items.filter { $0.kind != .song }
        let songPicks = store.picks.items.filter { $0.kind == .song }
        NavigationStack {
            List {
                if let song = player.current {
                    NavigationLink {
                        NowPlayingView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(song.title)
                                    .lineLimit(1)
                                Text(song.artist)
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
                        sheet = .fastDownload
                    } label: {
                        FastDownloadRow()
                    }
                }

                NavigationLink(value: BrowseRoute.path(.root)) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Add Music")
                            Text("Browse and search Plex and Subsonic")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }

                if store.picks.items.isEmpty {
                    emptyState
                } else {
                    Section {
                        if !songPicks.isEmpty {
                            NavigationLink(value: LibraryRoute.songs) {
                                SongsRow(count: songPicks.count)
                            }
                        }
                        ForEach(collections, id: \.key) { pick in
                            NavigationLink(value: LibraryRoute.pick(pick.key)) {
                                PickRow(pick: pick)
                            }
                        }
                    } footer: {
                        Text(storageSummary)
                    }
                }

                Button {
                    sheet = .quality
                } label: {
                    LabeledContent("Quality", value: store.quality.title)
                }
            }
            .navigationTitle("Cue")
            .navigationDestination(for: LibraryRoute.self) { route in
                CollectionScreen(route: route)
            }
            .navigationDestination(for: BrowseRoute.self) { route in
                switch route {
                case let .path(path):
                    BrowseScreen(path: path)
                case let .item(item):
                    BrowseItemScreen(item: item)
                }
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .fastDownload:
                    FastDownloadScreen()
                case .quality:
                    QualityPicker(current: store.hasChosenQuality ? store.quality : nil) { quality in
                        self.sheet = nil
                        store.setQuality(quality)
                    }
                }
            }
            // Asked once a launch until answered; songs come down at the
            // recommended quality meanwhile.
            .task(id: needsQuality) {
                if needsQuality, sheet == nil, !hasAskedQuality {
                    hasAskedQuality = true
                    sheet = .quality
                }
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
            Text("Tap Add Music to browse your Plex or Subsonic library, or choose Add to Apple Watch in Cue on your iPhone.")
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

private struct SongsRow: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note")
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading) {
                Text("Songs")
                Text(count == 1 ? "1 song" : "\(count) songs")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
        if !pick.subtitle.isEmpty {
            return pick.subtitle
        }
        return songs.count == 1 ? "1 song" : "\(songs.count) songs"
    }
}

/// Which quality songs come down at — asked the first time there's music
/// to fetch, and changed from the library screen.
struct QualityPicker: View {
    var current: WatchDownloadQuality?
    let choose: (WatchDownloadQuality) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(WatchDownloadQuality.allCases) { quality in
                        Button {
                            choose(quality)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(quality == .recommended ? "\(quality.title) (Recommended)" : quality.title)
                                    Text(quality.detail)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if quality == current {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Your watch has much less room than your iPhone, so songs can be converted to MP3 as they download. Changing it converts the songs already here.")
                }
            }
            .navigationTitle("Quality")
        }
    }
}
