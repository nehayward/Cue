import Defaults
import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI

/// The download manager: the songs kept on this device, the albums and
/// playlists they came from, the books downloaded whole, and how
/// downloading behaves (and the caches, which take room here too) — one
/// face each, switched by the segmented control under the title. A Files folder in iCloud Drive reports how much of it
/// is here under Settings. Reached from Settings, and on Books
/// from the Audiobooks tab's Downloads.
struct DownloadsScreen: View {
    /// The screen's faces. Songs is home: what's on the device is what the
    /// screen is for, and it's what the Storage row's size describes. Albums
    /// and Playlists show while there are any of them; Books while there are
    /// books to download, or any downloaded.
    private enum Tab: String, CaseIterable, Identifiable {
        case songs, albums, playlists, books, settings

        var id: Self { self }

        /// The tab a container is listed under: a playlist's own, anything
        /// else downloaded whole under Albums.
        static func of(_ container: DownloadManager.Container) -> Tab {
            [.playlist, .libraryPlaylist].contains(container.type) ? .playlists : .albums
        }

        var title: LocalizedStringKey {
            switch self {
            case .songs: "Songs"
            case .albums: "Albums"
            case .playlists: "Playlists"
            case .books: "Books"
            case .settings: "Settings"
            }
        }
    }

    @State private var manager = DownloadManager.shared
    @State private var cache = PlaybackCache.shared
    @State private var apple = AppleDownloadsIndex.shared
    @State private var files = FilesLibraryService.shared
    @State private var cloudSummary: (local: Int, remote: Int)?
    /// The face picked here; until one is, the one the screen opened on.
    @State private var picked: Tab?
    @State private var isConfirmingClearCache = false
    @State private var isConfirmingRemoveAll = false
    @AppStorage(AppStorageKeys.hasPlexAudiobooks) private var hasPlexBooks = false

    /// Opens on the books rather than the songs.
    var opensOnBooks = false
    /// Storage from Settings, the caches at the foot of its Settings tab
    /// making it the place for everything that takes room here; Downloads
    /// from the library, Home and Audiobooks.
    var title: LocalizedStringKey = "Downloads"

    private var tab: Tab {
        picked ?? (opensOnBooks ? .books : .songs)
    }

    var body: some View {
        // Each is a filter and sort over every download; once per render,
        // not once per mention.
        let active = manager.active
        // Books' files are listed with their books, under Books.
        let completed = manager.completedSongs

        List {
            switch tab {
            case .songs:
                songsSections(active: active.filter { $0.isBookFile != true }, completed: completed)
            case .albums:
                containerSections(kind: .albums)
            case .playlists:
                containerSections(kind: .playlists)
            case .books:
                booksSections
            case .settings:
                settingsSections
            }
        }
        // A fresh list per tab: switching lands at the top of the new one
        // rather than wherever the last was scrolled to.
        .id(tab)
        .pinnedUnderTitle {
            Picker("Show", selection: Binding { tab } set: { picked = $0 }) {
                ForEach(Tab.allCases.filter(shows)) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !active.isEmpty {
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
                            manager.cancel(keys: active.map(\.key))
                        } label: {
                            Label("Cancel All", systemImage: "xmark.circle")
                        }
                    } label: {
                        Label("Downloads", systemImage: "ellipsis")
                    }
                }
            }
        }
        .task {
            apple.refreshIfNeeded()
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

    // MARK: - Songs

    /// What's coming down and what's here, song by song, under the free
    /// meter when there is one.
    @ViewBuilder
    private func songsSections(active: [DownloadManager.Item], completed: [DownloadManager.Item]) -> some View {
        if let remaining = manager.remainingFreeSlots {
            freeLimitSection(remaining: remaining)
        }

        if !active.isEmpty {
            Section {
                ForEach(active) { item in
                    activeRow(item)
                }
            } header: {
                Text("Downloading")
            } footer: {
                Text(manager.allowsCellular
                     ? "Downloads carry on when Cue is in the background, with their progress on the Lock Screen, and pick up where they left off after a relaunch."
                     : "Downloads carry on when Cue is in the background, with their progress on the Lock Screen, and pick up where they left off after a relaunch. On cellular they wait for Wi‑Fi and start by themselves when it's back; tap the antenna to download one over cellular now.")
            }
        }

        if !completed.isEmpty {
            let completedBytes = completed.reduce(0) { $0 + ($1.fileSize ?? 0) }
            // A section of its own above the songs, found without scrolling
            // past every one of them; so near the top, it asks first.
            Section {
                Button(role: .destructive) {
                    isConfirmingRemoveAll = true
                } label: {
                    Text("Remove All Downloads")
                        .frame(maxWidth: .infinity)
                }
                .confirmationDialog(
                    completed.count == 1 ? "Remove 1 downloaded song?" : "Remove all \(completed.count) downloaded songs?",
                    isPresented: $isConfirmingRemoveAll,
                    titleVisibility: .visible
                ) {
                    Button("Remove All Downloads", role: .destructive) {
                        manager.removeAllCompletedSongs()
                    }
                } message: {
                    Text("They're taken off this iPhone and can be downloaded again.")
                }
            }

            Section {
                ForEach(completed) { item in
                    completedRow(item)
                }
                .onDelete { offsets in
                    for index in offsets where completed.indices.contains(index) {
                        manager.remove(key: completed[index].key)
                    }
                }
            } header: {
                Text("On This Device")
            } footer: {
                let withLyrics = completed.filter { DownloadLyrics.shared.withLyrics.contains($0.key) }.count
                Text("\(completed.count == 1 ? "1 song" : "\(completed.count) songs") • \(ByteCountFormatter.string(fromByteCount: completedBytes, countStyle: .file))\(withLyrics > 0 ? " • lyrics for \(withLyrics == completed.count ? "all" : "\(withLyrics)") offline" : ""). Kept until you remove them; not included in backups.")
            }
        } else if active.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No Downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text(manager.remainingFreeSlots == nil
                         ? "Download a Plex or Subsonic song, album or playlist from its menu — or an album's download button — to keep it on this device."
                         : "Download a Plex or Subsonic song, album or playlist from its menu — or an album's download button — to keep it on this device. Up to \(DownloadManager.freeSongLimit) songs are free.")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }

        if !apple.songs.isEmpty {
            appleSection
        }
    }

    /// The Music app's downloads, counted rather than listed: they're the
    /// system's, not the manager's — nothing here to pause, remove or count
    /// against the free limit — and they're browsed as a library of their
    /// own under Downloaded on the Apple Library page.
    private var appleSection: some View {
        Section {
            NavigationLink(value: RouterDestination.downloaded(service: .apple)) {
                LabeledContent {
                    Text(apple.songs.count == 1 ? "1 song" : "\(apple.songs.count.formatted()) songs")
                } label: {
                    Label("Downloaded in Music", systemImage: "arrow.down.circle.fill")
                }
            }
        } header: {
            Text("Apple Music")
        } footer: {
            Text("Songs the Music app has downloaded. Cue plays them on this device with or without a network; adding and removing them is done in Music, and they don't count toward the free limit.")
        }
    }

    // MARK: - Albums and playlists

    /// Whether a tab is offered: Albums and Playlists while there are any
    /// (books aside), Books by its own rule, and the one showing always.
    private func shows(_ candidate: Tab) -> Bool {
        if candidate == tab { return true }
        switch candidate {
        case .albums, .playlists:
            return manager.containers.values.contains { $0.type != .audiobook && Tab.of($0) == candidate }
        case .books:
            return showsBooks
        case .songs, .settings:
            return true
        }
    }

    /// What was downloaded whole, still coming or all here, each removable
    /// as one: the albums under Albums, the playlists under Playlists. The
    /// songs themselves are listed under Songs; books have a tab of their
    /// own.
    @ViewBuilder
    private func containerSections(kind: Tab) -> some View {
        let isKind = { (container: DownloadManager.Container) in
            container.type != .audiobook && Tab.of(container) == kind
        }
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
                Text("On This Device")
            } footer: {
                Text("Swipe to remove every song of a \(noun) at once. The songs themselves are listed under Songs; remove one there and the rest stay here.")
            }
        } else if downloading.isEmpty {
            Section {
                ContentUnavailableView {
                    Label(kind == .playlists ? "No Playlists" : "No Albums", systemImage: kind == .playlists ? "music.note.list" : "square.stack")
                } description: {
                    Text("Download a Plex or Subsonic \(noun) whole — from its menu or its download button — and it's listed here as one thing, to remove as one.")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
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

    /// Whether the Books tab shows: books to download (the Audiobooks tab's
    /// rule, an Audiobookshelf sign-in or a Plex server that had books), or
    /// any downloaded or on their way, or the screen opened on them.
    private var showsBooks: Bool {
        let features = CoreFeatures.shared
        return tab == .books
            || (features.isEnabled(.audiobookshelf) && AudiobookshelfAPI.shared.isConfigured)
            || (features.isEnabled(.plex) && hasPlexBooks)
            || manager.containers.values.contains { $0.type == .audiobook }
    }

    /// The books downloaded whole, coming down or all here: each its cover,
    /// how far into it the listener is, and the room it takes; a tap opens
    /// its page, a swipe removes it, a long press plays it.
    @ViewBuilder
    private var booksSections: some View {
        let downloading = manager.activeContainers.filter { $0.type == .audiobook }
        let downloaded = manager.completedContainers.filter { $0.type == .audiobook }

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
            } header: {
                Text("On This Device")
            } footer: {
                Text("\(downloaded.count == 1 ? "1 book" : "\(downloaded.count) books") • \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)). Swipe to remove a book from this device; it stays on its server, and your place in it is kept.")
            }
        } else if downloading.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No Books", systemImage: "books.vertical")
                } description: {
                    Text("Download a Plex or Audiobookshelf book from its page or its menu to listen with no network.")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
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

    /// How downloading behaves: the playback cache, cellular, and the Files
    /// folder in iCloud Drive when there is one.
    @ViewBuilder
    private var settingsSections: some View {
        @Bindable var manager = manager
        @Bindable var cache = cache

        Section {
            Picker(selection: $cache.songLimit) {
                Text("Off").tag(0)
                Text("25 songs").tag(25)
                Text("50 songs").tag(50)
                Text("100 songs").tag(100)
                Text("250 songs").tag(250)
                Text("500 songs").tag(500)
            } label: {
                Label("Keep Recent Songs", systemImage: "clock.arrow.circlepath")
            }
            if cache.isEnabled {
                Picker(selection: $cache.prefetchCount) {
                    Text("Next song").tag(1)
                    Text("Next 3 songs").tag(3)
                    Text("Next 5 songs").tag(5)
                    Text("Next 10 songs").tag(10)
                } label: {
                    Label("Fetch Ahead", systemImage: "arrow.down.circle.dotted")
                }
                Toggle(isOn: $cache.allowsCellular) {
                    Label("Fill Over Cellular", systemImage: "antenna.radiowaves.left.and.right")
                }
                LabeledContent {
                    Text(cache.entries.isEmpty
                         ? "Nothing yet"
                         : "\(cache.entries.count == 1 ? "1 song" : "\(cache.entries.count) songs") • \(ByteCountFormatter.string(fromByteCount: cache.totalBytes, countStyle: .file))")
                } label: {
                    Label("Cached", systemImage: "internaldrive")
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
                        Label("Clear Cache", systemImage: "trash")
                    }
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

        Section {
            Toggle(isOn: $manager.allowsCellular) {
                Label("Use Cellular Data", systemImage: "antenna.radiowaves.left.and.right")
            }
        } header: {
            Text("Downloads")
        } footer: {
            Text("Off, downloads on cellular wait for Wi‑Fi and start by themselves when it's back, and Cue asks before downloading over cellular. Songs fetched ahead from iCloud Drive wait for Wi‑Fi unless the playback cache allows cellular.")
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
                    Label("Free Downloads", systemImage: "arrow.down.circle")
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
                Label("Stream from iCloud", systemImage: "icloud.and.arrow.down")
            }
            if cache.streamsFromCloud, !cache.streamedCloudIDs.isEmpty {
                LabeledContent {
                    Text(cache.streamedCloudIDs.count == 1 ? "1 song" : "\(cache.streamedCloudIDs.count.formatted()) songs")
                } label: {
                    Label("Fetched to Play", systemImage: "play.circle")
                }
            }
            if let cloudSummary {
                LabeledContent {
                    Text("\(cloudSummary.local.formatted()) of \((cloudSummary.local + cloudSummary.remote).formatted()) songs")
                } label: {
                    Label("On This Device", systemImage: "internaldrive")
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

private extension View {
    /// A bar pinned under the navigation title. On iOS 26 the system draws
    /// the scroll edge beneath it, as it does for the bar itself; before,
    /// a material band does the same job.
    @ViewBuilder
    func pinnedUnderTitle<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            safeAreaBar(edge: .top, spacing: 0, content: content)
        } else {
            safeAreaInset(edge: .top, spacing: 0) {
                content()
                    .background(.bar)
            }
        }
    }
}

#Preview {
    NavigationStack {
        DownloadsScreen()
    }
    .withEnvironments()
}
