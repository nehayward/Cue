import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI

/// The download manager: the songs kept on this device, the albums and
/// playlists they came from, and how downloading behaves — one face each,
/// switched by the segmented control under the title. Songs opens on how
/// much room Cue takes and what's left on the device. A Files folder in
/// iCloud Drive reports how much of it is here under Settings. Reached from
/// Settings › Storage, and from Manage on a Downloaded page, which opens
/// Settings here in a sheet.
struct DownloadsScreen: View {
    /// The screen's three faces. Songs is home: what's on the device is what
    /// the screen is for, and it's what the Storage row's size describes.
    private enum Tab: String, CaseIterable, Identifiable {
        case songs, albums, settings

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .songs: "Songs"
            case .albums: "Albums"
            case .settings: "Settings"
            }
        }
    }

    /// How the downloaded songs are listed. Largest first is for making
    /// room; newest first is how they're kept.
    private enum SongOrder: String, CaseIterable, Identifiable {
        case newest, largest, alphabetical

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .newest: "Recently Downloaded"
            case .largest: "Largest"
            case .alphabetical: "Title"
            }
        }
    }

    @Environment(Router.self) private var router: Router?
    @State private var manager = DownloadManager.shared
    @State private var cache = PlaybackCache.shared
    @State private var apple = AppleDownloadsIndex.shared
    @State private var files = FilesLibraryService.shared
    @State private var cloudSummary: (local: Int, remote: Int)?
    @State private var tab: Tab = .songs
    @State private var songOrder: SongOrder = .newest
    @State private var isConfirmingClearCache = false
    @State private var isConfirmingRemoveAll = false
    /// Room left on the device, read when the screen opens and whenever a
    /// download lands or goes.
    @State private var availableBytes: Int64?

    var body: some View {
        // Each is a filter and sort over every download; once per render,
        // not once per mention.
        let active = manager.active
        let completed = manager.completed

        List {
            switch tab {
            case .songs:
                songsSections(active: active, completed: completed)
            case .albums:
                albumsSections
            case .settings:
                settingsSections
            }
        }
        // A fresh list per tab: switching lands at the top of the new one
        // rather than wherever the last was scrolled to.
        .id(tab)
        .pinnedUnderTitle {
            Picker("Show", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle("Downloads")
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
        .task(id: completed.count) {
            availableBytes = Self.availableCapacity()
        }
    }

    // MARK: - Songs

    /// What's coming down and what's here, song by song, under the free
    /// meter when there is one.
    @ViewBuilder
    private func songsSections(active: [DownloadManager.Item], completed: [DownloadManager.Item]) -> some View {
        let completedBytes = completed.reduce(0) { $0 + ($1.fileSize ?? 0) }
        if completedBytes + cache.totalBytes > 0 {
            storageSection(completed: completed, completedBytes: completedBytes)
        }

        if let remaining = manager.remainingFreeSlots {
            freeLimitSection(remaining: remaining)
        }

        if !active.isEmpty {
            Section {
                downloadingSummary(active)
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
            Section {
                ForEach(ordered(completed)) { item in
                    completedRow(item)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                manager.remove(key: item.key)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
                // Asks first: it's every song at once, and getting them
                // back means downloading them all again.
                Button(role: .destructive) {
                    isConfirmingRemoveAll = true
                } label: {
                    Text("Remove All Downloads")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .listRowBackground(Color.clear)
                .confirmationDialog("Remove all downloads?", isPresented: $isConfirmingRemoveAll, titleVisibility: .visible) {
                    Button(role: .destructive) {
                        manager.removeAllCompleted()
                    } label: {
                        Text(completed.count == 1 ? "Remove 1 Song" : "Remove \(completed.count) Songs")
                    }
                } message: {
                    Text("They're taken off this device and stay on the server, to download again whenever you like. Songs still downloading carry on.")
                }
            } header: {
                HStack {
                    Text("Downloaded")
                    Spacer()
                    Menu {
                        Picker("Sort By", selection: $songOrder) {
                            ForEach(SongOrder.allCases) { order in
                                Text(order.title).tag(order)
                            }
                        }
                    } label: {
                        Label(songOrder.title, systemImage: "arrow.up.arrow.down")
                            .font(.footnote)
                    }
                    .textCase(nil)
                }
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

    // MARK: - Albums

    /// What was downloaded whole, still coming or all here, each removable
    /// as one. The songs themselves are listed under Songs.
    @ViewBuilder
    private var albumsSections: some View {
        let downloading = manager.activeContainers
        let downloaded = manager.completedContainers

        if !downloading.isEmpty {
            containersSection(downloading) {
                Text("Downloading")
            } footer: {
                Text("Swipe to cancel an album or playlist; the songs of it already here go too.")
            }
        }

        if !downloaded.isEmpty {
            containersSection(downloaded) {
                Text("Downloaded")
            } footer: {
                Text("Swipe to remove every song of an album or playlist at once. The songs themselves are listed under Songs; remove one there and the rest stay here.")
            }
        } else if downloading.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No Albums or Playlists", systemImage: "square.stack")
                } description: {
                    Text("Download a Plex or Subsonic album or playlist whole — from its menu or its download button — and it's listed here as one thing, to remove as one.")
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
    }

    // MARK: - Storage

    /// How much room Cue takes, at a glance: downloads and the playback
    /// cache as one bar, each with its size, and what's left on the device.
    /// The bar is Cue's own share split between the two — against the
    /// whole device it would be a sliver.
    private func storageSection(completed: [DownloadManager.Item], completedBytes: Int64) -> some View {
        let cacheBytes = cache.totalBytes
        let cacheCount = cache.entries.count
        return Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ByteCountFormatter.string(fromByteCount: completedBytes + cacheBytes, countStyle: .file))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Text("used by Cue")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let availableBytes {
                        Text("\(ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)) free")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                StorageBar(segments: [
                    .init(id: "downloads", bytes: completedBytes, color: .accentColor),
                    .init(id: "cache", bytes: cacheBytes, color: .orange),
                ])

                HStack(alignment: .top, spacing: 20) {
                    storageLegend(
                        "Downloads",
                        detail: "\(completed.count == 1 ? "1 song" : "\(completed.count.formatted()) songs") • \(ByteCountFormatter.string(fromByteCount: completedBytes, countStyle: .file))",
                        color: .accentColor
                    )
                    storageLegend(
                        "Playback Cache",
                        detail: cache.isEnabled
                            ? "\(cacheCount == 1 ? "1 song" : "\(cacheCount.formatted()) songs") • \(ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file))"
                            : "Off",
                        color: .orange
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func storageLegend(_ title: LocalizedStringKey, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    /// Room left on the device for things that matter to the person — what
    /// the system would free for a download, not only what's free now.
    private static func availableCapacity() -> Int64? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    // MARK: - Downloading

    /// Everything coming down in one line — how many to go and how far
    /// along — with the control most often wanted beside it, rather than
    /// only in the menu.
    private func downloadingSummary(_ active: [DownloadManager.Item]) -> some View {
        let running = active.filter(\.isActive).count
        let fraction = active.reduce(0.0) { $0 + $1.progress } / Double(max(active.count, 1))
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(running > 0
                     ? (running == 1 ? "1 song to go" : "\(running) songs to go")
                     : (active.count == 1 ? "1 song stopped" : "\(active.count) songs stopped"))
                    .font(.subheadline.weight(.medium))
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            }
            Button(running > 0 ? "Pause All" : "Resume All") {
                HapticManager.shared.fireHaptic(.buttonPress)
                if running > 0 {
                    manager.pauseAll()
                } else {
                    manager.resumeAll()
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    /// The downloaded songs in the order picked in the section's menu.
    /// `completed` comes newest first.
    private func ordered(_ items: [DownloadManager.Item]) -> [DownloadManager.Item] {
        switch songOrder {
        case .newest:
            items
        case .largest:
            items.sorted { ($0.fileSize ?? 0) > ($1.fileSize ?? 0) }
        case .alphabetical:
            items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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
                    Text("\(counts.downloaded) of \(counts.total) songs")
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
                    Text(counts.total == 1 ? "1 song" : "\(counts.total) songs")
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

/// A capsule split into coloured runs, each as long as its share of the
/// total. A run with anything in it keeps a few points so it never
/// vanishes beside a much bigger one.
private struct StorageBar: View {
    struct Segment: Identifiable {
        let id: String
        let bytes: Int64
        let color: Color
    }

    let segments: [Segment]

    var body: some View {
        let visible = segments.filter { $0.bytes > 0 }
        let total = Double(max(visible.reduce(0) { $0 + $1.bytes }, 1))
        GeometryReader { proxy in
            let spacing: CGFloat = 2
            let width = proxy.size.width - spacing * CGFloat(max(visible.count - 1, 0))
            HStack(spacing: spacing) {
                ForEach(visible) { segment in
                    segment.color
                        .frame(width: max(4, width * CGFloat(Double(segment.bytes) / total)))
                }
            }
        }
        .frame(height: 8)
        .background(.quaternary)
        .clipShape(Capsule())
        .accessibilityHidden(true)
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
