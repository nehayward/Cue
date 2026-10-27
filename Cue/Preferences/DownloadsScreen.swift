import Defaults
import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI

/// A page of Storage's own: what's coming down, and what's kept here by
/// kind, each listed whole and removable from there.
public enum StoragePage: String, Hashable, Sendable {
    case downloading, songs, albums, playlists, books

    var title: LocalizedStringKey {
        switch self {
        case .downloading: "Downloading"
        case .songs: "Songs"
        case .albums: "Albums"
        case .playlists: "Playlists"
        case .books: "Books"
        }
    }

    /// The page a container is listed on: a book under Books, a playlist
    /// under Playlists, anything else downloaded whole under Albums.
    static func of(_ container: DownloadManager.Container) -> StoragePage {
        if container.type == .audiobook { return .books }
        return [.playlist, .libraryPlaylist].contains(container.type) ? .playlists : .albums
    }
}

/// Storage: what Cue keeps on this device and how it behaves, as one list.
/// The room taken on top (songs, books, the playback cache), then a row
/// each for what's coming down and what's kept — songs, albums, playlists,
/// books, Apple Music's — opening its own page (`StoragePage`) to look
/// through and remove, then the settings: cellular, the playback cache, a
/// Files folder in iCloud Drive, and the caches. Reached from Settings and
/// the Downloads tab's gear; the Audiobooks tab's Downloads opens Books.
struct DownloadsScreen: View {
    @State private var manager = DownloadManager.shared
    @State private var cache = PlaybackCache.shared
    @State private var apple = AppleDownloadsIndex.shared
    @State private var files = FilesLibraryService.shared
    @State private var cloudSummary: (local: Int, remote: Int)?
    /// The room left on the device, read as Storage opens.
    @State private var freeBytes: Int64?
    @State private var isConfirmingClearCache = false
    @State private var isConfirmingRemoveAll = false
    @State private var isConfirmingRemoveAllBooks = false
    @State private var isConfirmingRemoveAllContainers = false

    /// Nil for Storage itself; one of its pages otherwise.
    var page: StoragePage? = nil

    var body: some View {
        List {
            switch page {
            case nil:
                overviewSections
            case .downloading:
                downloadingSections
            case .songs:
                songsSections
            case .albums:
                containerSections(kind: .albums)
            case .playlists:
                containerSections(kind: .playlists)
            case .books:
                booksSections
            }
        }
        .navigationTitle(page?.title ?? "Storage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarContent
        }
        .confirmationDialog(
            manager.completedSongs.count == 1 ? "Remove 1 downloaded song?" : "Remove all \(manager.completedSongs.count) downloaded songs?",
            isPresented: $isConfirmingRemoveAll,
            titleVisibility: .visible
        ) {
            Button("Remove All Songs", role: .destructive) {
                manager.removeAllCompletedSongs()
            }
        } message: {
            Text("They're taken off this device and can be downloaded again. Books stay.")
        }
        .confirmationDialog(
            downloadedBooks.count == 1 ? "Remove 1 downloaded book?" : "Remove all \(downloadedBooks.count) downloaded books?",
            isPresented: $isConfirmingRemoveAllBooks,
            titleVisibility: .visible
        ) {
            Button("Remove All Books", role: .destructive) {
                manager.removeAllBooks()
            }
        } message: {
            Text("They're taken off this device and stay on their servers, with your place in each kept. Songs stay.")
        }
        .confirmationDialog(
            removeAllContainersTitle,
            isPresented: $isConfirmingRemoveAllContainers,
            titleVisibility: .visible
        ) {
            Button(page == .playlists ? "Remove All Playlists" : "Remove All Albums", role: .destructive) {
                for container in containers(on: page) {
                    manager.removeContainer(key: container.key)
                }
            }
        } message: {
            Text("Their songs are taken off this device, except those another download still holds, and can be downloaded again.")
        }
        .task {
            guard page == nil else { return }
            apple.refreshIfNeeded()
            files.startCloudMonitor()
            freeBytes = Self.deviceFreeBytes()
            await refreshCloudSummary()
        }
        .onDisappear {
            guard page == nil else { return }
            files.stopCloudMonitor()
        }
        .onChange(of: files.cloudProgress.isEmpty) {
            guard page == nil else { return }
            Task { await refreshCloudSummary() }
        }
    }

    /// Each page's own actions: the downloads' Pause, Resume and Cancel
    /// All, or removing every song or book at once.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        switch page {
        case .downloading where !manager.active.isEmpty:
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    let held = manager.cellularHeldKeys
                    if !held.isEmpty {
                        Button {
                            manager.allowCellular(forKeys: held)
                        } label: {
                            Label(held.count == 1 ? "Download Now Over Cellular" : "Download \(held.count) Now Over Cellular", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        Divider()
                    }
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
                        manager.cancel(keys: manager.active.map(\.key))
                    } label: {
                        Label("Cancel All", systemImage: "xmark.circle")
                    }
                    .tint(.red)
                } label: {
                    Label("Downloads", systemImage: "ellipsis")
                }
            }
        case .songs where !manager.completedSongs.isEmpty:
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        isConfirmingRemoveAll = true
                    } label: {
                        Label("Remove All Songs", systemImage: "trash")
                    }
                    .tint(.red)
                } label: {
                    Label("Songs", systemImage: "ellipsis")
                }
            }
        case .albums where !containers(on: .albums).isEmpty, .playlists where !containers(on: .playlists).isEmpty:
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        isConfirmingRemoveAllContainers = true
                    } label: {
                        Label(page == .playlists ? "Remove All Playlists" : "Remove All Albums", systemImage: "trash")
                    }
                    .tint(.red)
                } label: {
                    Label(page == .playlists ? "Playlists" : "Albums", systemImage: "ellipsis")
                }
            }
        case .books where !downloadedBooks.isEmpty:
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        isConfirmingRemoveAllBooks = true
                    } label: {
                        Label("Remove All Books", systemImage: "trash")
                    }
                    .tint(.red)
                } label: {
                    Label("Books", systemImage: "ellipsis")
                }
            }
        default:
            ToolbarItem(placement: .primaryAction) {
                EmptyView()
            }
        }
    }

    private var downloadedBooks: [DownloadManager.Container] {
        manager.completedContainers.filter { $0.type == .audiobook }
    }

    /// The albums or playlists downloaded whole, here or on their way.
    private func containers(on page: StoragePage?) -> [DownloadManager.Container] {
        guard let page, [.albums, .playlists].contains(page) else { return [] }
        return manager.containers.values.filter { StoragePage.of($0) == page }
    }

    private var removeAllContainersTitle: String {
        let count = containers(on: page).count
        let noun = page == .playlists ? "playlist" : "album"
        return count == 1 ? "Remove 1 downloaded \(noun)?" : "Remove all \(count) downloaded \(noun)s?"
    }

    // MARK: - Storage

    /// The room taken, the free meter, a row for each kind of thing kept,
    /// and the settings under them.
    @ViewBuilder
    private var overviewSections: some View {
        let songs = manager.completedSongs
        let books = downloadedBooks
        let containers = Array(manager.containers.values)
        let albums = containers.filter { StoragePage.of($0) == .albums }.count
        let playlists = containers.filter { StoragePage.of($0) == .playlists }.count
        let hasBooks = containers.contains { $0.type == .audiobook }
        let isDownloading = !manager.active.isEmpty
        let parts = [
            StorageUsageBar.Part(name: "Songs", bytes: songs.reduce(0) { $0 + ($1.fileSize ?? 0) }, color: StorageTile.songs.colors[0]),
            StorageUsageBar.Part(name: "Books", bytes: books.reduce(0) { $0 + bookBytes($1) }, color: StorageTile.books.colors[0]),
            StorageUsageBar.Part(name: "Playback Cache", bytes: cache.totalBytes, color: StorageTile.cache.colors[0]),
        ].filter { $0.bytes > 0 }

        if !parts.isEmpty || freeBytes != nil {
            usageSection(parts)
        }

        if let remaining = manager.remainingFreeSlots {
            freeLimitSection(remaining: remaining)
        }

        if isDownloading || !songs.isEmpty || albums + playlists > 0 || hasBooks || !apple.songs.isEmpty {
            Section {
                if isDownloading {
                    NavigationLink(value: RouterDestination.storagePage(.downloading)) {
                        downloadingRow
                    }
                }
                if !songs.isEmpty {
                    pageRow(.songs, tile: .songs, count: songs.count)
                }
                if albums > 0 {
                    pageRow(.albums, tile: .albums, count: albums)
                }
                if playlists > 0 {
                    pageRow(.playlists, tile: .playlists, count: playlists)
                }
                if hasBooks {
                    pageRow(.books, tile: .books, count: books.count)
                }
                if !apple.songs.isEmpty {
                    // The Music app's downloads, counted rather than kept:
                    // nothing of them is Cue's to pause, remove or count
                    // against the free limit.
                    NavigationLink(value: RouterDestination.downloaded(service: .apple)) {
                        LabeledContent {
                            Text(apple.songs.count.formatted())
                                .monospacedDigit()
                        } label: {
                            Label {
                                Text("Downloaded in Music")
                            } icon: {
                                StorageTile.appleMusic.icon
                            }
                        }
                    }
                }
            } footer: {
                Text(apple.songs.isEmpty
                     ? "Kept until you remove them, and left out of backups."
                     : "Kept until you remove them, and left out of backups. Apple Music's downloads are added and removed in the Music app, and don't count toward the free limit.")
            }
        } else {
            Section {
                ContentUnavailableView {
                    Label("No Downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text(manager.remainingFreeSlots == nil
                         ? "Download a Plex or Subsonic song, album or playlist, or a Plex or Audiobookshelf book, to keep it on this device."
                         : "Download a Plex or Subsonic song, album or playlist to keep it on this device. Up to \(DownloadManager.freeSongLimit) songs are free.")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }

        settingsSections
    }

    /// How much room Cue's songs, books and playback cache take, as one
    /// bar split between them.
    private func usageSection(_ parts: [StorageUsageBar.Part]) -> some View {
        let total = parts.reduce(0) { $0 + $1.bytes }
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
                        .font(.title2.bold())
                        .monospacedDigit()
                    Text("used by Cue")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    // What's left for more, beside what Cue takes.
                    if let freeBytes {
                        Text("\(ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)) free")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .lineLimit(1)
                if !parts.isEmpty {
                    StorageUsageBar(parts: parts)
                }
                // Each its name over its size, so three fit a phone's width
                // without one wrapping.
                HStack(alignment: .top, spacing: 18) {
                    ForEach(parts) { part in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(part.color)
                                    .frame(width: 8, height: 8)
                                Text(part.name)
                                    .foregroundStyle(.secondary)
                            }
                            Text(ByteCountFormatter.string(fromByteCount: part.bytes, countStyle: .file))
                                .monospacedDigit()
                                .padding(.leading, 13)
                        }
                        .lineLimit(1)
                    }
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
        }
    }

    /// A row opening one of Storage's pages, with how many it holds.
    private func pageRow(_ page: StoragePage, tile: StorageTile, count: Int) -> some View {
        NavigationLink(value: RouterDestination.storagePage(page)) {
            LabeledContent {
                Text(count.formatted())
                    .monospacedDigit()
            } label: {
                Label {
                    Text(page.title)
                } icon: {
                    tile.icon
                }
            }
        }
    }

    /// What's coming down: the run's bar while it moves, else how many
    /// stopped.
    private var downloadingRow: some View {
        Label {
            if manager.musicSummary.remainingDownloads > 0 {
                DownloadingProgress(summary: manager.musicSummary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Downloading")
                    Text(manager.stoppedCount == 1 ? "1 stopped" : "\(manager.stoppedCount) stopped")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } icon: {
            StorageTile.downloading.icon
        }
    }

    // MARK: - Downloading

    /// Everything still coming down, stopped or waiting: the books whole,
    /// the songs one by one.
    @ViewBuilder
    private var downloadingSections: some View {
        let songs = manager.active.filter { $0.isBookFile != true }
        let books = manager.activeContainers.filter { $0.type == .audiobook }

        if !books.isEmpty {
            Section {
                ForEach(books) { container in
                    bookRow(container)
                }
                .onDelete { offsets in
                    for index in offsets where books.indices.contains(index) {
                        manager.removeContainer(key: books[index].key)
                    }
                }
            } header: {
                Text("Books")
            } footer: {
                Text("Swipe to cancel a book; the files of it already here go too.")
            }
        }

        if !songs.isEmpty {
            Section {
                ForEach(songs) { item in
                    activeRow(item)
                }
            } header: {
                if !books.isEmpty {
                    Text("Songs")
                }
            } footer: {
                Text(manager.allowsCellular
                     ? "Downloads carry on when Cue is in the background, with their progress on the Lock Screen, and pick up where they left off after a relaunch."
                     : "Downloads carry on when Cue is in the background, with their progress on the Lock Screen, and pick up where they left off after a relaunch. On cellular they wait for Wi‑Fi and start by themselves when it's back; tap the antenna to download one over cellular now.")
            }
        }

        if songs.isEmpty, books.isEmpty {
            emptySection("Nothing Downloading", systemImage: "arrow.down.circle", description: "Everything you've downloaded is on this device.")
        }
    }

    // MARK: - Songs

    /// The songs kept here, one by one, each with its size.
    @ViewBuilder
    private var songsSections: some View {
        let completed = manager.completedSongs
        if completed.isEmpty {
            emptySection("No Songs", systemImage: "music.note", description: "Download a Plex or Subsonic song, album or playlist from its menu, or an album's download button, to keep it on this device.")
        } else {
            let completedBytes = completed.reduce(0) { $0 + ($1.fileSize ?? 0) }
            Section {
                ForEach(completed) { item in
                    completedRow(item)
                }
                .onDelete { offsets in
                    for index in offsets where completed.indices.contains(index) {
                        manager.remove(key: completed[index].key)
                    }
                }
            } footer: {
                let withLyrics = completed.filter { DownloadLyrics.shared.withLyrics.contains($0.key) }.count
                Text("\(completed.count == 1 ? "1 song" : "\(completed.count) songs") • \(ByteCountFormatter.string(fromByteCount: completedBytes, countStyle: .file))\(withLyrics > 0 ? " • lyrics for \(withLyrics == completed.count ? "all" : "\(withLyrics)") offline" : ""). Swipe to remove one.")
            }
        }
    }

    // MARK: - Albums and playlists

    /// What was downloaded whole, still coming or all here, each removable
    /// as one. The songs themselves are listed under Songs.
    @ViewBuilder
    private func containerSections(kind: StoragePage) -> some View {
        let isKind = { (container: DownloadManager.Container) in StoragePage.of(container) == kind }
        let downloading = manager.activeContainers.filter(isKind)
        let downloaded = manager.completedContainers.filter(isKind)
        let noun = kind == .playlists ? "playlist" : "album"

        if !downloading.isEmpty {
            containersSection(downloading) {
                Text("Downloading")
            } footer: {
                Text("Swipe to cancel a whole \(noun); the songs of it already here go too.")
            }
        }

        if !downloaded.isEmpty {
            containersSection(downloaded) {
                EmptyView()
            } footer: {
                Text("Swipe to remove every song of a \(noun) at once. Its songs are listed under Songs too; remove one there and the rest stay.")
            }
        } else if downloading.isEmpty {
            emptySection(kind == .playlists ? "No Playlists" : "No Albums", systemImage: kind == .playlists ? "music.note.list" : "square.stack", description: "Download a Plex or Subsonic \(noun) whole, from its menu or its download button, and it's listed here to remove as one.")
        }
    }

    private func containersSection<Header: View, Footer: View>(
        _ containers: [DownloadManager.Container],
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        Section {
            ForEach(containers) { container in
                containerRow(container)
            }
            .onDelete { offsets in
                for index in offsets where containers.indices.contains(index) {
                    manager.removeContainer(key: containers[index].key)
                }
            }
        } header: {
            header()
        } footer: {
            footer()
        }
    }

    // MARK: - Books

    /// The books downloaded whole, coming down or all here: each its cover,
    /// how far into it the listener is, and the room it takes; a tap opens
    /// its page, a swipe removes it, a long press plays it.
    @ViewBuilder
    private var booksSections: some View {
        let downloading = manager.activeContainers.filter { $0.type == .audiobook }
        let downloaded = downloadedBooks

        if !downloading.isEmpty {
            Section {
                ForEach(downloading) { container in
                    bookRow(container)
                }
                .onDelete { offsets in
                    for index in offsets where downloading.indices.contains(index) {
                        manager.removeContainer(key: downloading[index].key)
                    }
                }
            } header: {
                Text("Downloading")
            } footer: {
                Text("Swipe to cancel a book; the files of it already here go too.")
            }
        }

        if !downloaded.isEmpty {
            let bytes = downloaded.reduce(0) { $0 + bookBytes($1) }
            Section {
                ForEach(downloaded) { container in
                    bookRow(container)
                }
                .onDelete { offsets in
                    for index in offsets where downloaded.indices.contains(index) {
                        manager.removeContainer(key: downloaded[index].key)
                    }
                }
            } footer: {
                Text("\(downloaded.count == 1 ? "1 book" : "\(downloaded.count) books") • \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)). Swipe to remove a book from this device; it stays on its server, and your place in it is kept.")
            }
        } else if downloading.isEmpty {
            emptySection("No Books", systemImage: "books.vertical", description: "Download a Plex or Audiobookshelf book from its page or its menu to listen with no network.")
        }
    }

    /// The room left on the device for things that matter to the person
    /// using it (`volumeAvailableCapacityForImportantUsage`, what Settings ▸
    /// General ▸ Storage reports), shown to them beside what Cue takes:
    /// disk space reason 85F4.1 in the privacy manifest.
    private static func deviceFreeBytes() -> Int64? {
        let values = try? URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// A page with nothing on it, saying how things get there.
    private func emptySection(_ title: LocalizedStringKey, systemImage: String, description: LocalizedStringKey) -> some View {
        Section {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(description)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func bookRow(_ container: DownloadManager.Container) -> some View {
        let book = AudiobookDownloads.book(for: container)
        let state = manager.containerState(key: container.key)
        let counts = manager.trackCounts(forContainer: container.key)
        let stopped = manager.stoppedTrackCount(forContainer: container.key)
        let progress = AudiobookProgressStore.shared.progress(for: book)
        return NavigationLink(value: RouterDestination.audiobookDetail(content: book)) {
            HStack(spacing: 12) {
                artwork(container.artwork)
                VStack(alignment: .leading, spacing: 2) {
                    Text(container.title)
                        .lineLimit(1)
                    Text([container.subtitle, progress.flatMap(AudiobookFormat.remaining) ?? ""].filter { !$0.isEmpty }.joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if case let .downloading(fraction) = state {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .tint(stopped > 0 ? .red : .accentColor)
                        Text(stopped > 0
                             ? "\(container.type.downloadCount(stopped)) stopped"
                             : "\(counts.downloaded) of \(container.type.downloadCount(counts.total))")
                            .font(.caption2)
                            .foregroundStyle(stopped > 0 ? .red : .secondary)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
                if state == .downloaded {
                    VStack(alignment: .trailing, spacing: 2) {
                        container.service.image
                            .frame(width: 14, height: 14)
                        Text(ByteCountFormatter.string(fromByteCount: bookBytes(container), countStyle: .file))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if stopped > 0 {
                    Button {
                        manager.resumeDownload(contentsOf: book)
                    } label: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Retry Download")
                }
            }
        }
        .contextMenu {
            AudiobookMenuItems(book: book)
        }
    }

    /// The room a book's files take on this device.
    private func bookBytes(_ container: DownloadManager.Container) -> Int64 {
        container.trackKeys.reduce(0) { $0 + (manager.items[$1]?.fileSize ?? 0) }
    }

    // MARK: - Settings

    /// How downloading behaves: cellular, the playback cache, the Files
    /// folder in iCloud Drive when there is one, and the caches.
    @ViewBuilder
    private var settingsSections: some View {
        @Bindable var manager = manager
        @Bindable var cache = cache

        Section {
            Toggle(isOn: $manager.allowsCellular) {
                Label {
                    Text("Use Cellular Data")
                } icon: {
                    StorageTile.cellular.icon
                }
            }
        } header: {
            Text("Downloads")
        } footer: {
            Text("Off, downloads on cellular wait for Wi‑Fi and start by themselves when it's back, and Cue asks before downloading over cellular. Songs fetched ahead from iCloud Drive wait for Wi‑Fi unless the playback cache allows cellular.")
        }

        Section {
            Picker(selection: $cache.songLimit) {
                Text("Off").tag(0)
                Text("25 songs").tag(25)
                Text("50 songs").tag(50)
                Text("100 songs").tag(100)
                Text("250 songs").tag(250)
                Text("500 songs").tag(500)
            } label: {
                Label {
                    Text("Keep Recent Songs")
                } icon: {
                    StorageTile.recent.icon
                }
            }
            // Its value grey, as Settings' are, not in the accent.
            .tint(.secondary)
            if cache.isEnabled {
                Picker(selection: $cache.prefetchCount) {
                    Text("Next song").tag(1)
                    Text("Next 3 songs").tag(3)
                    Text("Next 5 songs").tag(5)
                    Text("Next 10 songs").tag(10)
                } label: {
                    Label {
                        Text("Fetch Ahead")
                    } icon: {
                        StorageTile.fetchAhead.icon
                    }
                }
                .tint(.secondary)
                Toggle(isOn: $cache.allowsCellular) {
                    Label {
                        Text("Fill Over Cellular")
                    } icon: {
                        StorageTile.cellular.icon
                    }
                }
                LabeledContent {
                    Text(cache.entries.isEmpty
                         ? "Nothing yet"
                         : "\(cache.entries.count == 1 ? "1 song" : "\(cache.entries.count) songs") • \(ByteCountFormatter.string(fromByteCount: cache.totalBytes, countStyle: .file))")
                } label: {
                    Label {
                        Text("Cached")
                    } icon: {
                        StorageTile.cache.icon
                    }
                }
                if !cache.inFlight.isEmpty {
                    Label {
                        Text(cache.inFlight.count == 1 ? "Fetching 1 song ahead…" : "Fetching \(cache.inFlight.count) songs ahead…")
                            .foregroundStyle(.secondary)
                    } icon: {
                        ProgressView()
                    }
                }
                if !cache.entries.isEmpty {
                    // Not a red row: clearing is safe (everything comes back
                    // when played), so it asks once instead of shouting.
                    Button {
                        isConfirmingClearCache = true
                    } label: {
                        Label {
                            Text("Clear Cache")
                        } icon: {
                            StorageTile.clear.icon
                        }
                    }
                    // In the text's colour, as Settings' rows are.
                    .tint(.primary)
                    .confirmationDialog("Clear the playback cache?", isPresented: $isConfirmingClearCache, titleVisibility: .visible) {
                        Button(role: .destructive) {
                            cache.clear()
                        } label: {
                            Text(cache.entries.count == 1 ? "Clear 1 Song" : "Clear \(cache.entries.count) Songs")
                        }
                    } message: {
                        Text("Songs kept for playback are taken off this device and fetched again when they come up. Downloads you chose yourself stay.")
                    }
                }
            }
        } header: {
            Text("Playback Cache")
        } footer: {
            Text("Songs coming up in the on-device queue are fetched before they play, and recent ones kept, so playback holds through a tunnel or a dead spot. The least recently played goes first when the cap is reached. Covers Plex and Subsonic, and a Files folder in iCloud Drive when streaming is on below. Downloads you choose yourself are kept separately.")
        }

        if files.isConfigured, files.isCloudFolder {
            cloudSection
        }

        CachesSection()
    }

    // MARK: - Free limit

    /// How much of the free allowance is used, here and on the Apple Watch,
    /// and the way past it: one card, the meter over a row that opens the
    /// paywall once the meter is mostly full — early enough to read as
    /// "here's what's coming", not as a wall.
    private func freeLimitSection(remaining: Int) -> some View {
        let limit = DownloadManager.freeSongLimit
        let held = manager.heldAgainstLimit
        let onWatch = WatchSyncService.shared.heldOnWatch
        return Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label {
                        Text("Free Downloads")
                    } icon: {
                        StorageTile.downloading.icon
                    }
                    Spacer()
                    Text("\(held) of \(limit) songs")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ProgressView(value: Double(held), total: Double(limit))
                    .progressViewStyle(.linear)
                    .tint(remaining == 0 ? .red : .accentColor)
                if onWatch > 0 {
                    Text("\(onWatch) of them on your Apple Watch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if remaining <= limit / 5 {
                // Plain, so the list's tint doesn't paint the whole label:
                // in the accent, the detail line was green on grey and
                // hard to read. The accent is the Upgrade capsule's alone.
                Button {
                    FeatureGate.shared.presentPaywall(PaywallReason(feature: .unlimitedDownloads))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accent.gradient)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Get Cue Super")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Unlimited downloads and books, on iPhone and Apple Watch.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text("Upgrade")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accent, in: Capsule())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } footer: {
            Text(remaining == 0
                 ? "Every free slot is taken. Remove a download to free one."
                 : "Songs here, on your Apple Watch and on their way count; removing one frees its slot.")
        }
    }

    private func containerRow(_ container: DownloadManager.Container) -> some View {
        let counts = manager.trackCounts(forContainer: container.key)
        let state = manager.containerState(key: container.key)
        return HStack(spacing: 12) {
            artwork(container.artwork)
            VStack(alignment: .leading, spacing: 2) {
                Text(container.title)
                    .lineLimit(1)
                Text([container.type.title, container.subtitle].filter { !$0.isEmpty }.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if case let .downloading(fraction) = state {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                    Text("\(counts.downloaded) of \(container.type.downloadCount(counts.total))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                container.service.image
                    .frame(width: 14, height: 14)
                if state == .downloaded {
                    Text(container.type.downloadCount(counts.total))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
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
            let heldForWiFi = manager.cellularHeldKeys.contains(item.key)
            Button {
                if heldForWiFi {
                    manager.offerCellular(forKeys: [item.key])
                    return
                }
                switch item.state {
                case .queued, .downloading, .waiting: manager.pause(key: item.key)
                case .paused, .failed: manager.resume(key: item.key)
                case .completed: break
                }
            } label: {
                Image(systemName: heldForWiFi
                      ? "antenna.radiowaves.left.and.right.circle.fill"
                      : item.isActive ? "pause.circle.fill" : "arrow.clockwise.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(heldForWiFi ? "Download Over Cellular" : item.isActive ? "Pause Download" : "Resume Download")
        }
        .swipeActions(edge: .leading) {
            if item.state == .waiting {
                Button {
                    manager.pause(key: item.key)
                } label: {
                    Label("Pause", systemImage: "pause")
                }
            }
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
                HStack(spacing: 4) {
                    // Its lyrics are kept with it, for listening offline.
                    if DownloadLyrics.shared.withLyrics.contains(item.key) {
                        Image(systemName: "quote.bubble.fill")
                            .accessibilityLabel("Lyrics saved")
                    }
                    Text(ByteCountFormatter.string(fromByteCount: item.fileSize ?? 0, countStyle: .file))
                }
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
        case .waiting:
            return manager.network == .none ? "Waiting for a connection" : "Waiting for Wi‑Fi"
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
        @Bindable var cache = cache
        return Section {
            Toggle(isOn: $cache.streamsFromCloud) {
                Label {
                    Text("Stream from iCloud")
                } icon: {
                    StorageTile.iCloud.icon
                }
            }
            if cache.streamsFromCloud, !cache.streamedCloudIDs.isEmpty {
                LabeledContent {
                    Text(cache.streamedCloudIDs.count == 1 ? "1 song" : "\(cache.streamedCloudIDs.count.formatted()) songs")
                } label: {
                    Label {
                        Text("Fetched to Play")
                    } icon: {
                        StorageTile.fetchAhead.icon
                    }
                }
            }
            if let cloudSummary {
                LabeledContent {
                    Text("\(cloudSummary.local.formatted()) of \((cloudSummary.local + cloudSummary.remote).formatted()) songs")
                } label: {
                    Label {
                        Text("On This Device")
                    } icon: {
                        StorageTile.cache.icon
                    }
                }
            } else {
                Label {
                    Text("Checking the folder…")
                        .foregroundStyle(.secondary)
                } icon: {
                    ProgressView()
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
                    Label {
                        Text("Download Everything")
                    } icon: {
                        StorageTile.iCloud.icon
                    }
                }
            }
            if let cloudSummary, cloudSummary.local > 0 {
                Button(role: .destructive) {
                    files.removeAllFromDevice()
                    Task { await refreshCloudSummary() }
                } label: {
                    Label {
                        Text("Remove Downloads from This Device")
                    } icon: {
                        StorageTile.remove.icon
                    }
                }
            }
        } header: {
            Text(files.folderName.map { "iCloud Drive • \($0)" } ?? "iCloud Drive")
        } footer: {
            Text("Streaming fetches songs from iCloud as they come up — the next \(PlaybackCache.cloudPrefetchCount) ahead — and takes them off the device again once they've dropped out of the playback cache, so the folder can stay in iCloud without filling this device. Songs you download yourself stay put. iCloud downloads are carried by the system, so they finish even when Cue is closed; removed songs stay in iCloud and download again when played.")
        }
    }

    private func refreshCloudSummary() async {
        guard files.isConfigured, files.isCloudFolder else {
            cloudSummary = nil
            return
        }
        cloudSummary = await files.cloudSummary()
    }
}

/// The tile beside each of Storage's rows, as Settings draws its own
/// (`SettingsIcon`): a white symbol on a colour of its own, never the
/// accent. Songs, books and the cache are the usage bar's colours too.
enum StorageTile {
    case downloading, songs, albums, playlists, books, appleMusic
    case cellular, recent, fetchAhead, cache, clear, iCloud, remove, images, library

    var symbol: String {
        switch self {
        case .downloading: "arrow.down"
        case .songs: "music.note"
        case .albums: "square.stack.fill"
        case .playlists: "music.note.list"
        case .books: "book.fill"
        case .appleMusic: "applelogo"
        case .cellular: "antenna.radiowaves.left.and.right"
        case .recent: "clock.arrow.circlepath"
        case .fetchAhead: "forward.fill"
        case .cache: "internaldrive.fill"
        case .clear: "trash.fill"
        case .iCloud: "icloud.fill"
        case .remove: "icloud.slash.fill"
        case .images: "photo.stack.fill"
        case .library: "externaldrive.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .downloading: [Color(red: 0.3, green: 0.8, blue: 0.55), Color(red: 0.1, green: 0.6, blue: 0.4)]
        case .songs: [Color(red: 0.35, green: 0.6, blue: 0.95), Color(red: 0.2, green: 0.45, blue: 0.85)]
        case .albums: [Color(red: 0.45, green: 0.45, blue: 0.95), Color(red: 0.3, green: 0.3, blue: 0.8)]
        case .playlists: [Color(red: 0.7, green: 0.5, blue: 0.95), Color(red: 0.55, green: 0.35, blue: 0.85)]
        case .books: [Color(red: 1.0, green: 0.62, blue: 0.25), Color(red: 0.95, green: 0.45, blue: 0.15)]
        case .appleMusic: [Color(red: 0.98, green: 0.35, blue: 0.45), Color(red: 0.9, green: 0.18, blue: 0.3)]
        case .cellular: [Color(red: 0.35, green: 0.85, blue: 0.45), Color(red: 0.2, green: 0.7, blue: 0.3)]
        case .recent, .cache, .images, .library: [Color(red: 0.55, green: 0.55, blue: 0.6), Color(red: 0.4, green: 0.4, blue: 0.45)]
        case .fetchAhead, .iCloud: [Color(red: 0.4, green: 0.75, blue: 0.95), Color(red: 0.25, green: 0.6, blue: 0.9)]
        case .clear, .remove: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.9, green: 0.25, blue: 0.25)]
        }
    }

    var icon: SettingsIcon {
        SettingsIcon(symbol: symbol, colors: colors, padding: self == .appleMusic ? 7 : 8)
    }
}

/// The room Cue takes, as one bar split between what takes it.
private struct StorageUsageBar: View {
    struct Part: Identifiable {
        let name: String
        let bytes: Int64
        let color: Color

        var id: String { name }
    }

    let parts: [Part]

    private static let gap: CGFloat = 2

    var body: some View {
        let total = max(parts.reduce(0) { $0 + $1.bytes }, 1)
        GeometryReader { geometry in
            let width = geometry.size.width - Self.gap * CGFloat(max(parts.count - 1, 0))
            HStack(spacing: Self.gap) {
                ForEach(parts) { part in
                    part.color
                        .frame(width: max(3, width * CGFloat(part.bytes) / CGFloat(total)))
                }
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        DownloadsScreen()
    }
    .withEnvironments()
}
