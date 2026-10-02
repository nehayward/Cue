import SwiftUI
import WatchKit
import WatchSync

/// Where a library row goes: one pick's songs, or the songs added one at
/// a time.
enum LibraryRoute: Hashable {
    case pick(String)
    case songs
}

/// Where the home screen goes, besides the library.
enum HomeRoute: Hashable {
    case settings
    case downloads
    case nowPlaying
}

/// The watch's home: Downloads at the top (the count of songs here in its
/// title), then the lists of the library picked top right. Settings is top
/// left; search and Now Playing are in the bottom bar, out of the way while
/// the list scrolls. No title: the rows say what's what. The first time
/// there's music to fetch, it asks at what quality.
struct LibraryScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchPlayer.self) private var player
    @Environment(WatchAccounts.self) private var accounts
    @AppStorage("librarySource") private var chosenSource = WatchSource.plex.rawValue
    @State private var path = NavigationPath()
    @State private var sheet: Sheet?
    @State private var hasAskedQuality = false
    @State private var isScrolling = false

    private enum Sheet: String, Identifiable {
        case quality, library
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
                NavigationLink(value: HomeRoute.downloads) {
                    DownloadsRow()
                }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sheet = .library
                    } label: {
                        Image(systemName: "books.vertical")
                    }
                    .accessibilityLabel("Library")
                }
                // Search the library left, Now Playing right: the system's
                // own toolbar buttons, the waveform moving while music plays.
                ToolbarItemGroup(placement: .bottomBar) {
                    if let source {
                        TextFieldLink(prompt: Text("Search \(source.title)"), onSubmit: { text in
                            search(text, in: source)
                        }) {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel("Search \(source.title)")
                        .fadesWhileScrolling(isScrolling)
                    }
                    Spacer()
                    if player.current != nil {
                        Button {
                            path.append(HomeRoute.nowPlaying)
                        } label: {
                            Image(systemName: player.isPlaying ? "waveform" : "play.fill")
                                .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                        }
                        .accessibilityLabel("Now Playing")
                        .fadesWhileScrolling(isScrolling)
                    }
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .settings:
                    SettingsScreen()
                case .downloads:
                    DownloadsScreen()
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

    private func search(_ text: String, in source: WatchSource) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        path.append(BrowseRoute.path(.search(source, query)))
    }

    // MARK: - Library

    @ViewBuilder
    private var library: some View {
        if let source {
            Section {
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

private extension View {
    /// Out of the way while the list scrolls.
    func fadesWhileScrolling(_ isScrolling: Bool) -> some View {
        opacity(isScrolling ? 0 : 1)
            .allowsHitTesting(!isScrolling)
            .animation(.easeInOut(duration: 0.2), value: isScrolling)
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
