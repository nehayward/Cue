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
}

/// The watch's home: Downloads at the top (the count of songs here in its
/// title), then the lists of the library picked top right. Settings is top
/// left; the bottom bar has search, Now Playing in the middle and play on
/// the right edge (double tap presses it), hidden while the list scrolls
/// down. No title: the rows say what's what. Screens zoom out of the row
/// that opens them; Now Playing comes up as a sheet — the system's, so it
/// shows the iPhone's playback too when the watch has none. The widget
/// opens it on Downloads or Now Playing. The first time there's music to
/// fetch, it asks at what quality.
struct LibraryScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchPlayer.self) private var player
    @Environment(WatchAccounts.self) private var accounts
    @AppStorage("librarySource") private var chosenSource = WatchSource.plex.rawValue
    @State private var path = NavigationPath()
    @State private var sheet: Sheet?
    @State private var hasAskedQuality = false
    @State private var isBottomBarHidden = false
    @Namespace private var zoom

    private enum Sheet: String, Identifiable {
        case quality, library, nowPlaying
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
                .zoomSource(HomeRoute.downloads, in: zoom)
                library
            }
            .modifier(HidesBottomBarScrollingDown(isHidden: $isBottomBarHidden))
            .toolbar(isBottomBarHidden ? .hidden : .visible, for: .bottomBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        path.append(HomeRoute.settings)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .zoomSource(HomeRoute.settings, in: zoom)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sheet = .library
                    } label: {
                        Image(systemName: "books.vertical")
                    }
                    .accessibilityLabel("Library")
                }
                // Search left, Now Playing in the middle with its waveform
                // moving while music plays, play on the right edge (double
                // tap presses it).
                ToolbarItemGroup(placement: .bottomBar) {
                    if let source {
                        TextFieldLink(prompt: Text("Search \(source.title)")) {
                            Image(systemName: "magnifyingglass")
                        } onSubmit: { text in
                            search(text, in: source)
                        }
                        .accessibilityLabel("Search \(source.title)")
                    }
                    Spacer()
                    // Always there: with nothing on the watch, Now Playing
                    // shows what the iPhone's playing.
                    Button {
                        sheet = .nowPlaying
                    } label: {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                    }
                    .accessibilityLabel("Now Playing")
                    Spacer()
                    if player.current != nil || store.downloadedCount > 0 {
                        PrimaryPlayButton()
                    }
                }
            }
            // Each screen zooms out of the row or button that opened it.
            .navigationDestination(for: HomeRoute.self) { route in
                Group {
                    switch route {
                    case .settings:
                        SettingsScreen()
                    case .downloads:
                        DownloadsScreen()
                    }
                }
                .zoomDestination(route, in: zoom)
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                CollectionScreen(route: route)
                    .zoomDestination(route, in: zoom)
            }
            .navigationDestination(for: BrowseRoute.self) { route in
                Group {
                    switch route {
                    case let .path(path):
                        BrowseScreen(path: path)
                    case let .item(item):
                        BrowseItemScreen(item: item)
                    }
                }
                .zoomDestination(route, in: zoom)
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
                case .nowPlaying:
                    NowPlayingView()
                }
            }
            // From the Smart Stack widget.
            .onOpenURL { url in
                switch url.host() {
                case "downloads": path = NavigationPath([HomeRoute.downloads])
                case "nowplaying": sheet = .nowPlaying
                default: break
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
        .environment(\.zoomNamespace, zoom)
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
                    let route = BrowseRoute.path(.section(source, section))
                    NavigationLink(value: route) {
                        Label(section.title, systemImage: section.symbol)
                    }
                    .zoomSource(route, in: zoom)
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

/// Play and pause what's playing, or shuffle the downloads when nothing
/// is: the screen's primary action, so double tap (and the pinch on watches
/// that have it) presses it.
private struct PrimaryPlayButton: View {
    @Environment(WatchPlayer.self) private var player

    var body: some View {
        Button {
            if player.current == nil {
                player.playDownloads(shuffled: true)
            } else {
                player.togglePlayPause()
            }
        } label: {
            Image(systemName: player.current == nil ? "shuffle" : player.isPlaying ? "pause.fill" : "play.fill")
        }
        .accessibilityLabel(player.current == nil ? "Shuffle Downloads" : player.isPlaying ? "Pause" : "Play")
        .primaryHandGesture()
    }
}

extension View {
    /// Double tap presses this (watchOS 11).
    @ViewBuilder
    func primaryHandGesture() -> some View {
        if #available(watchOS 11.0, *) {
            handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}

/// Hides the bottom bar while the list scrolls down and brings it back
/// when it scrolls up or reaches the top, as iPhone toolbars minimize
/// (watchOS 11 reports the scroll position; before that, it stays).
private struct HidesBottomBarScrollingDown: ViewModifier {
    @Binding var isHidden: Bool

    func body(content: Content) -> some View {
        if #available(watchOS 11.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { previous, offset in
                let hide: Bool
                if offset < 12 {
                    hide = false
                } else if offset > previous + 2 {
                    hide = true
                } else if offset < previous - 2 {
                    hide = false
                } else {
                    return
                }
                guard hide != isHidden else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHidden = hide
                }
            }
        } else {
            content
        }
    }
}

/// The zoom from a row or button into the screen it opens (watchOS 11).
/// The routes are the ids, so a source and its screen meet on the value
/// that links them.
struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The home screen's, for rows further in to zoom from.
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func zoomSource(_ id: some Hashable, in namespace: Namespace.ID?) -> some View {
        if #available(watchOS 11.0, *), let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomDestination(_ id: some Hashable, in namespace: Namespace.ID?) -> some View {
        if #available(watchOS 11.0, *), let namespace {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
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
