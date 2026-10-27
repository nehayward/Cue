import SwiftUI
import WatchSync

/// The watch's settings, top left on the home screen: the room downloads
/// take, as the iPhone's Storage shows it (a bar split between songs and
/// books beside the watch's free space), the way to them and to retrying
/// what failed, taking songs or books off, the quality songs come down at,
/// which sign-ins the iPhone has shared, and the version and build.
struct SettingsScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchAccounts.self) private var accounts
    @State private var isChoosingQuality = false
    @State private var removal: Removal?
    /// The room left on the watch, read as Settings opens.
    @State private var freeBytes: Int64?

    /// What a Remove button in Manage takes off, asked first.
    private enum Removal: Identifiable {
        case music, books, everything

        var id: Self { self }

        var title: String {
            switch self {
            case .music: "Remove All Songs?"
            case .books: "Remove All Books?"
            case .everything: "Remove All Downloads?"
            }
        }
    }

    var body: some View {
        let bookBytes = store.bookBytesUsed
        let hasMusic = !store.musicPicks.isEmpty
        let hasBooks = !store.books.isEmpty
        List {
            Section {
                WatchStorageUsage(songBytes: max(0, store.bytesUsed - bookBytes), bookBytes: bookBytes, freeBytes: freeBytes)
                NavigationLink(value: HomeRoute.downloads) {
                    TileRow(title: "Downloads", detail: store.contentsText, symbol: "arrow.down", color: .downloads)
                }
                if store.failedCount > 0 {
                    Button {
                        store.retryAllFailed()
                    } label: {
                        TileRow(
                            title: "Retry Failed",
                            detail: WatchDownloadStore.countText(store.failedCount, files: store.remainingIncludesBooks),
                            symbol: "arrow.clockwise",
                            color: .remove
                        )
                    }
                }
            } header: {
                Text("Storage")
            }

            if hasMusic || hasBooks {
                // Songs and books apart, as on the iPhone; everything only
                // when there are both.
                Section {
                    if hasMusic {
                        Button(role: .destructive) {
                            removal = .music
                        } label: {
                            TileRow(title: "Remove All Songs", symbol: "music.note", color: .remove)
                        }
                    }
                    if hasBooks {
                        Button(role: .destructive) {
                            removal = .books
                        } label: {
                            TileRow(title: "Remove All Books", symbol: "book.fill", color: .remove)
                        }
                    }
                    if hasMusic, hasBooks {
                        Button(role: .destructive) {
                            removal = .everything
                        } label: {
                            TileRow(title: "Remove All", symbol: "trash.fill", color: .remove)
                        }
                    }
                } header: {
                    Text("Manage")
                } footer: {
                    Text("They come off this watch and your iPhone's list, and stay on your server. A book's place is kept.")
                }
            }

            Section {
                Button {
                    isChoosingQuality = true
                } label: {
                    LabeledContent("Quality", value: store.quality.title)
                }
            } footer: {
                Text("\(store.quality.detail). Books come down as your server keeps them.")
            }

            Section {
                LabeledContent("Plex", value: accounts.hasPlex ? "Signed In" : "Off")
                LabeledContent("Subsonic", value: accounts.hasSubsonic ? "Signed In" : "Off")
                LabeledContent("Audiobookshelf", value: accounts.hasAudiobookshelf ? "Signed In" : "Off")
            } header: {
                Text("Accounts")
            } footer: {
                Text("Sign in on your iPhone, then open Cue there once to bring the sign-ins here.")
            }

            Section {
                LabeledContent("Version", value: Self.version)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $isChoosingQuality) {
            QualityPicker(current: store.quality) { quality in
                isChoosingQuality = false
                store.setQuality(quality)
            }
        }
        .confirmationDialog(removal?.title ?? "", isPresented: Binding { removal != nil } set: { if !$0 { removal = nil } }, titleVisibility: .visible, presenting: removal) { removal in
            Button("Remove", role: .destructive) {
                switch removal {
                case .music: store.removeAllMusic()
                case .books: store.removeAllBooks()
                case .everything: store.removeAll()
                }
            }
        } message: { _ in
            Text("They come off this watch and your iPhone's list. They stay on your server.")
        }
        .task {
            freeBytes = Self.watchFreeBytes()
        }
    }

    /// The room left on the watch, shown to the person beside what Cue
    /// takes: disk space reason 85F4.1 in the watch's privacy manifest.
    /// The plain capacity, as watchOS has no "for important usage" figure.
    private static func watchFreeBytes() -> Int64? {
        let values = try? URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    /// The version and build, as "2026.8 (674)".
    private static let version: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }()
}

/// The room Cue takes on the watch, as the iPhone's Storage shows its own:
/// the total large, a bar of songs and books against what's free, and a
/// line each under it.
private struct WatchStorageUsage: View {
    let songBytes: Int64
    let bookBytes: Int64
    let freeBytes: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Self.size(songBytes + bookBytes))
                    .font(.title3.bold())
                    .monospacedDigit()
                Text("used")
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            bar
            VStack(alignment: .leading, spacing: 2) {
                legend("Songs", songBytes, TileColor.songs.color)
                if bookBytes > 0 {
                    legend("Books", bookBytes, TileColor.books.color)
                }
                if let freeBytes {
                    legend("Free", freeBytes, .gray.opacity(0.4))
                }
            }
            .font(.footnote)
        }
        .padding(.vertical, 4)
    }

    /// Songs, books and what's free side by side, each by its share, so
    /// the bar says how full the watch is as well as what fills it.
    private var bar: some View {
        let parts: [(Int64, Color)] = [
            (songBytes, TileColor.songs.color),
            (bookBytes, TileColor.books.color),
            (freeBytes ?? 0, .gray.opacity(0.4)),
        ].filter { $0.0 > 0 }
        let total = max(parts.reduce(0) { $0 + $1.0 }, 1)
        return GeometryReader { geometry in
            let width = geometry.size.width - 2 * CGFloat(max(parts.count - 1, 0))
            HStack(spacing: 2) {
                ForEach(parts.indices, id: \.self) { index in
                    parts[index].1
                        .frame(width: max(3, width * CGFloat(parts[index].0) / CGFloat(total)))
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private func legend(_ name: String, _ bytes: Int64, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(name)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(Self.size(bytes))
                .monospacedDigit()
        }
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// The colours of Settings' tiles, the iPhone's Storage ones.
private enum TileColor {
    case downloads, songs, books, remove

    var color: Color {
        switch self {
        case .downloads: Color(red: 0.2, green: 0.7, blue: 0.47)
        case .songs: Color(red: 0.3, green: 0.53, blue: 0.9)
        case .books: Color(red: 0.97, green: 0.53, blue: 0.2)
        case .remove: Color(red: 0.95, green: 0.32, blue: 0.32)
        }
    }
}

/// A row of Settings: a white symbol on a coloured tile, as the iPhone's
/// settings draw theirs, the title, and a line under it.
private struct TileRow: View {
    let title: String
    var detail: String? = nil
    let symbol: String
    let color: TileColor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(color.color.gradient, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                // Two lines at most: the watch's width cut "Remove All
                // Books" short on the smaller sizes.
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Which quality songs come down at — asked the first time there's music
/// to fetch, and changed in Settings.
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
