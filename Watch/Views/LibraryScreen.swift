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
    /// What the iPhone plays, while the card shows it.
    case phoneNowPlaying
    /// The queue the iPhone plays from, from its player.
    case phoneQueue
}

/// A library the home screen lists under Downloads, picked top right: a
/// music server's lists, or Audiobooks.
private enum HomeLibrary: Hashable {
    case music(WatchSource)
    case audiobooks

    /// As kept in the defaults: the server's, or "audiobooks".
    var rawValue: String {
        switch self {
        case let .music(source): source.rawValue
        case .audiobooks: "audiobooks"
        }
    }

    var title: String {
        switch self {
        case let .music(source): source.title
        case .audiobooks: "Audiobooks"
        }
    }

    var symbol: String {
        switch self {
        case .music(.subsonic): "externaldrive.connected.to.line.below"
        case .music: "server.rack"
        case .audiobooks: "book"
        }
    }
}

/// The watch's home: what's playing at the top, a card on its cover's
/// gradient that opens its player (the iPhone's, in a player of its own,
/// while the watch has nothing playing), where play and pause are, then
/// the library picked top right, led by Downloads (the count of songs here
/// in its title): a music server's lists with search as the last row, or
/// Audiobooks, the books on the watch and the servers' shelves of them.
/// With the iPhone out of reach, what's on the watch leads instead:
/// Downloads and the book last listened to, over the library. Settings is
/// top left. No title: the rows say what's what. Screens zoom out of the
/// row that opens them. The widget opens it on Downloads or Now Playing,
/// and watchOS, bringing Cue up as the iPhone starts playing, on the
/// iPhone's player.
/// The first time there's music to fetch, it asks at what quality.
struct LibraryScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchPlayer.self) private var player
    @Environment(PhoneNowPlaying.self) private var phone
    @Environment(WatchAccounts.self) private var accounts
    @Environment(WatchBookStore.self) private var bookStore
    @AppStorage("librarySource") private var chosenSource = WatchSource.plex.rawValue
    @State private var path = NavigationPath()
    @State private var sheet: Sheet?
    @State private var hasAskedQuality = false
    @Namespace private var zoom

    private enum Sheet: String, Identifiable {
        case quality, library
        var id: String { rawValue }
    }

    /// Books come down as they are, so only music asks.
    private var needsQuality: Bool {
        !store.hasChosenQuality && !store.musicPicks.isEmpty
    }

    /// The music libraries there are sign-ins for, then Audiobooks while
    /// there are books on the watch or a server with them.
    private var libraries: [HomeLibrary] {
        let music = WatchSource.music
            .filter { $0 == .plex ? accounts.hasPlex : accounts.hasSubsonic }
            .map(HomeLibrary.music)
        let hasBooks = !store.books.isEmpty || accounts.hasBooks
        return hasBooks ? music + [.audiobooks] : music
    }

    /// The one chosen, while it's there; else the first there is.
    private var library: HomeLibrary? {
        libraries.first { $0.rawValue == chosenSource } ?? libraries.first
    }

    /// The card is the iPhone's while the watch has nothing playing:
    /// nothing loaded here, paused while the iPhone plays, or both paused
    /// and the iPhone the one that played last (or the only one this
    /// launch).
    private var showsPhone: Bool {
        guard let playing = phone.current, !player.isPlaying else { return false }
        if player.current == nil || playing.isPlaying { return true }
        return (phone.lastPlayedAt ?? .distantPast) >= (player.lastPlayedAt ?? .distantPast)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if player.current != nil || showsPhone {
                    // The player of what the card shows: the system's Now
                    // Playing picks its own source, which with a book
                    // loaded here is the watch's, not the iPhone's.
                    let route = showsPhone ? HomeRoute.phoneNowPlaying : .nowPlaying
                    Button {
                        path.append(route)
                    } label: {
                        NowPlayingCard(showsPhone: showsPhone)
                    }
                    .buttonStyle(CardButtonStyle())
                    .zoomSource(route, in: zoom)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                if !phone.isPhoneInReach {
                    onThisWatch
                }
                switch library {
                case let .music(source)?:
                    lists(of: source)
                case .audiobooks?:
                    audiobooks
                case nil:
                    noLibrary
                }
            }
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
            }
            // Each screen zooms out of the row or button that opened it.
            .navigationDestination(for: HomeRoute.self) { route in
                Group {
                    switch route {
                    case .settings:
                        SettingsScreen()
                    case .downloads:
                        DownloadsScreen()
                    case .nowPlaying:
                        NowPlayingScreen()
                    case .phoneNowPlaying:
                        PhoneNowPlayingScreen()
                    case .phoneQueue:
                        PhoneQueueScreen()
                    }
                }
                .zoomDestination(route, in: zoom)
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                CollectionScreen(route: route)
                    .zoomDestination(route, in: zoom)
            }
            .navigationDestination(for: BookRoute.self) { route in
                BookScreen(key: route.key)
                    .zoomDestination(route, in: zoom)
            }
            .navigationDestination(for: BrowseRoute.self) { route in
                Group {
                    switch route {
                    case let .path(path):
                        BrowseScreen(path: path)
                    case let .item(item):
                        if item.pick?.kind == .audiobook {
                            BrowseBookScreen(item: item)
                        } else {
                            BrowseItemScreen(item: item)
                        }
                    }
                }
                .zoomDestination(route, in: zoom)
            }
            .sheet(item: $sheet, onDismiss: {
                // Closed without a choice: the recommended quality it's been
                // using stands, and it isn't asked again.
                if hasAskedQuality, !store.hasChosenQuality {
                    store.setQuality(store.quality)
                }
            }) { sheet in
                switch sheet {
                case .quality:
                    QualityPicker(current: store.hasChosenQuality ? store.quality : nil) { quality in
                        self.sheet = nil
                        store.setQuality(quality)
                    }
                case .library:
                    LibraryPicker(libraries: libraries, current: library) { chosen in
                        self.sheet = nil
                        chosenSource = chosen.rawValue
                    }
                }
            }
            // From the Smart Stack widget.
            .onOpenURL { url in
                switch url.host() {
                case "downloads": path = NavigationPath([HomeRoute.downloads])
                case "nowplaying": path = NavigationPath([HomeRoute.nowPlaying])
                default: break
                }
            }
            // watchOS opened Cue because the iPhone started playing: its
            // player, from wherever the app was left. Left alone while it's
            // already on show, so it doesn't open again.
            .onChange(of: phone.wantsPlayer, initial: true) { _, wants in
                guard wants else { return }
                phone.didOpenPlayer()
                let phonePlayer = NavigationPath([HomeRoute.phoneNowPlaying])
                if path != phonePlayer {
                    path = phonePlayer
                }
            }
            // Asked once, the first time there's music to fetch; songs come
            // down at the recommended quality meanwhile, and closing it
            // keeps that.
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

    /// What's on the watch, at the top of whichever library is on show, or
    /// over it with the iPhone out of reach.
    private var downloads: some View {
        NavigationLink(value: HomeRoute.downloads) {
            DownloadsRow()
        }
        .zoomSource(HomeRoute.downloads, in: zoom)
    }

    /// With the iPhone out of reach, the watch plays what's on it: that
    /// leads, Downloads and the book last listened to, to play at once.
    private var onThisWatch: some View {
        Section {
            downloads
            if let latest = recentBooks.first {
                bookBanner(latest)
            }
        } header: {
            Text("On This Watch")
        }
    }

    private func lists(of source: WatchSource) -> some View {
        Section {
            if phone.isPhoneInReach {
                downloads
            }
            ForEach(WatchBrowseSection.allCases, id: \.self) { section in
                let route = BrowseRoute.path(.section(source, section))
                NavigationLink(value: route) {
                    Label(section.title, systemImage: section.symbol)
                }
                .zoomSource(route, in: zoom)
            }
            TextFieldLink(prompt: Text("Search \(source.title)")) {
                Label("Search", systemImage: "magnifyingglass")
            } onSubmit: { text in
                search(text, in: source)
            }
            .accessibilityLabel("Search \(source.title)")
        } header: {
            Text(source.title)
        }
    }

    private var noLibrary: some View {
        Section {
            if phone.isPhoneInReach {
                downloads
            }
            Text("Open Cue on your iPhone, signed in to Plex, Subsonic or Audiobookshelf, to browse your library here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        } header: {
            Text("Library")
        }
    }

    // MARK: - Audiobooks

    /// The three books on the watch last listened to and not finished,
    /// newest first.
    private var recentBooks: [WatchPick] {
        let places = bookStore.places
        return store.books
            .compactMap { pick in places[pick.key].map { (pick: pick, place: $0) } }
            .filter { !$0.place.isFinished && $0.place.position > 0 }
            .sorted { $0.place.updatedAt > $1.place.updatedAt }
            .prefix(3)
            .map(\.pick)
    }

    /// The books last listened to — the latest a banner that plays it (on
    /// top with Downloads while the iPhone's out of reach), the two before
    /// it side by side — then Downloads, the other books on the watch, and
    /// the servers' shelves: what's in progress, and every book on each.
    private var audiobooks: some View {
        let recent = recentBooks
        return Section {
            if phone.isPhoneInReach, let latest = recent.first {
                bookBanner(latest)
            }
            if recent.count > 1 {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(recent.dropFirst(), id: \.key) { pick in
                        let route = BookRoute(key: pick.key)
                        Button {
                            path.append(route)
                        } label: {
                            BookTile(pick: pick)
                        }
                        .buttonStyle(CardButtonStyle())
                        .zoomSource(route, in: zoom)
                    }
                    // One book beside the banner keeps a tile's width.
                    if recent.count == 2 {
                        Color.clear
                            .frame(maxWidth: .infinity)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if phone.isPhoneInReach {
                downloads
            }
            ForEach(store.books.filter { pick in !recent.contains { $0.key == pick.key } }, id: \.key) { pick in
                let route = BookRoute(key: pick.key)
                NavigationLink(value: route) {
                    BookRow(pick: pick)
                }
                .zoomSource(route, in: zoom)
            }
            if accounts.hasBooks {
                shelf(.listening, title: "Continue Listening", symbol: "clock.arrow.circlepath")
                if accounts.hasPlex, accounts.plexHasBooks {
                    shelf(.all(.plex), title: "Plex Books", symbol: "server.rack")
                }
                if accounts.hasAudiobookshelf {
                    shelf(.all(.audiobookshelf), title: "Audiobookshelf", symbol: "book.closed.fill")
                }
            }
        } header: {
            Text("Audiobooks")
        }
    }

    private func bookBanner(_ pick: WatchPick) -> some View {
        Button {
            playOrPause(pick)
        } label: {
            BookBanner(pick: pick)
        }
        .buttonStyle(CardButtonStyle())
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    /// Plays a book from where it was left, or pauses it while it plays.
    private func playOrPause(_ pick: WatchPick) {
        if player.book?.key == pick.key, player.isPlaying {
            player.pause()
        } else if !player.playBook(pick) {
            WKInterfaceDevice.current().play(.failure)
        }
    }

    private func shelf(_ shelf: WatchBookShelf, title: String, symbol: String) -> some View {
        let route = BrowseRoute.path(.books(shelf))
        return NavigationLink(value: route) {
            Label(title, systemImage: symbol)
        }
        .zoomSource(route, in: zoom)
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

/// The libraries there are sign-ins for, and Audiobooks, to list on the
/// home screen.
private struct LibraryPicker: View {
    let libraries: [HomeLibrary]
    let current: HomeLibrary?
    let choose: (HomeLibrary) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(libraries, id: \.self) { library in
                    Button {
                        choose(library)
                    } label: {
                        HStack {
                            Label(library.title, systemImage: library.symbol)
                            Spacer(minLength: 0)
                            if library == current {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
                if libraries.isEmpty {
                    Text("Sign in to Plex, Subsonic or Audiobookshelf in Cue on your iPhone, and open it once, to bring the sign-ins here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Library")
        }
    }
}
