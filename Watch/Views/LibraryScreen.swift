import SwiftUI
import WatchKit
import WatchSync

/// Where a library row goes: one pick's songs, or the songs added one at
/// a time.
enum LibraryRoute: Hashable {
    case pick(String)
    case songs
}

/// Where the home screen's toolbar goes.
enum HomeRoute: Hashable {
    case settings
    case nowPlaying
}

/// The watch's home, one screen deep for everything: what's downloaded at
/// the top (with Fast Download while songs are still to come), and below
/// it the library named top right — its search and lists, a tap from
/// here. Settings is top left; Now Playing sits bottom centre while
/// something plays, out of the way while the list scrolls. No title: the
/// sections say what's what. The first time there's music to fetch, it
/// asks at what quality.
struct LibraryScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchPlayer.self) private var player
    @Environment(WatchAccounts.self) private var accounts
    @AppStorage("librarySource") private var chosenSource = WatchSource.plex.rawValue
    @State private var path = NavigationPath()
    @State private var sheet: Sheet?
    @State private var hasAskedQuality = false
    @State private var isScrolling = false
    @State private var query = ""

    private enum Sheet: String, Identifiable {
        case fastDownload, quality, library
        var id: String { rawValue }
    }

    private var needsQuality: Bool {
        !store.hasChosenQuality && !store.picks.items.isEmpty
    }

    /// The libraries there are sign-ins for.
    private var sources: [WatchSource] {
        WatchSource.allCases.filter { $0 == .plex ? accounts.hasPlex : accounts.hasSubsonic }
    }

    /// The one chosen, while there's a sign-in for it; else the one there is.
    private var source: WatchSource? {
        sources.first { $0.rawValue == chosenSource } ?? sources.first
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                downloads
                library
            }
            .modifier(ScrollPhaseReader(isScrolling: $isScrolling))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        path.append(HomeRoute.settings)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                // The library browsed below, named; tap to change it.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sheet = .library
                    } label: {
                        Text(source?.title ?? "Library")
                    }
                    .accessibilityHint("Chooses the library to browse")
                }
                // The system's own look: a toolbar button with the waveform
                // that moves while music plays.
                ToolbarItemGroup(placement: .bottomBar) {
                    if player.current != nil {
                        Spacer()
                        Button {
                            path.append(HomeRoute.nowPlaying)
                        } label: {
                            Image(systemName: player.isPlaying ? "waveform" : "play.fill")
                                .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                        }
                        .accessibilityLabel("Now Playing")
                        .opacity(isScrolling ? 0 : 1)
                        .allowsHitTesting(!isScrolling)
                        .animation(.easeInOut(duration: 0.2), value: isScrolling)
                        Spacer()
                    }
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .settings:
                    SettingsScreen()
                case .nowPlaying:
                    NowPlayingView()
                }
            }
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
                case .library:
                    LibraryPicker(sources: sources, current: source) { chosen in
                        self.sheet = nil
                        chosenSource = chosen.rawValue
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

    // MARK: - Downloads

    @ViewBuilder
    private var downloads: some View {
        let collections = store.picks.items.filter { $0.kind != .song }
        let songPicks = store.picks.items.filter { $0.kind == .song }
        Section {
            if store.remainingCount > 0 || store.fastPhase != .off {
                Button {
                    sheet = .fastDownload
                } label: {
                    FastDownloadRow()
                }
            }
            if !songPicks.isEmpty {
                NavigationLink(value: LibraryRoute.songs) {
                    SongsRow(count: songPicks.count, bytes: store.bytesUsed(by: store.songs(in: songPicks.map(\.key))))
                }
            }
            ForEach(collections, id: \.key) { pick in
                NavigationLink(value: LibraryRoute.pick(pick.key)) {
                    PickRow(pick: pick)
                }
            }
            if store.picks.items.isEmpty {
                Text("Nothing here yet. Find music below, or choose Add to Apple Watch in Cue on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        } header: {
            Text("Downloads")
        } footer: {
            if !store.picks.items.isEmpty {
                Text(storageSummary)
            }
        }
    }

    private var storageSummary: String {
        let size = ByteCountFormatter.string(fromByteCount: store.bytesUsed, countStyle: .file)
        let songs = store.downloadedCount == 1 ? "1 song" : "\(store.downloadedCount) songs"
        return "\(songs) on this watch • \(size)"
    }

    // MARK: - Library

    @ViewBuilder
    private var library: some View {
        if let source {
            Section {
                TextField("Search \(source.title)", text: $query)
                    .onSubmit {
                        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        query = ""
                        path.append(BrowseRoute.path(.search(source, trimmed)))
                    }
                ForEach(WatchBrowseSection.allCases, id: \.self) { section in
                    NavigationLink(value: BrowseRoute.path(.section(source, section))) {
                        Label(section.title, systemImage: section.symbol)
                    }
                }
            } header: {
                Text(source.title)
            }
        } else {
            Section {
                Text("Open Cue on your iPhone, signed in to Plex or Subsonic, to browse your library here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } header: {
                Text("Library")
            }
        }
    }
}

/// Whether a list is being scrolled, for what should get out of its way.
/// Only watchOS 11 says; before it, nothing fades.
private struct ScrollPhaseReader: ViewModifier {
    @Binding var isScrolling: Bool

    func body(content: Content) -> some View {
        if #available(watchOS 11.0, *) {
            content.onScrollPhaseChange { _, phase in
                isScrolling = phase.isScrolling
            }
        } else {
            content
        }
    }
}

/// The libraries there are sign-ins for, to browse on the home screen.
private struct LibraryPicker: View {
    let sources: [WatchSource]
    let current: WatchSource?
    let choose: (WatchSource) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(sources, id: \.self) { source in
                    Button {
                        choose(source)
                    } label: {
                        HStack {
                            Label(source.title, systemImage: source == .plex ? "server.rack" : "externaldrive.connected.to.line.below")
                            Spacer(minLength: 0)
                            if source == current {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
                if sources.isEmpty {
                    Text("Sign in to Plex or Subsonic in Cue on your iPhone, and open it once, to bring the sign-ins here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Library")
        }
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
