import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// The Audiobooks tab: Continue Listening, the books not yet finished with
/// the one listened to last on top, each one tap from where it was left;
/// the books on this device; a section for each server, its newest books
/// with the way to every one; what was finished lately; and the words
/// looked up in the books' transcripts.
///
/// What's been listened to comes from two places: this device's history
/// (`PlayHistoryService`, which `AudiobookPlayer` writes the book to when
/// it plays) and Audiobookshelf's own list of books in progress, so a book
/// started in another app is here too. Both are ordered by when the book's
/// place last moved (`AudiobookProgressStore`), newest first.
struct AudiobooksScreen: View {
    @Environment(CoreFeatures.self) private var coreFeatures
    @Environment(MusicSearchService.self) private var musicSearchService
    @AppStorage(AppStorageKeys.hasPlexAudiobooks) private var hasPlexBooks = false

    /// This tab's own stack, never a shared router: two stacks bound to one
    /// path push each other.
    @State private var router = Router()
    @State private var store = AudiobookProgressStore.shared
    @State private var removals = ContinueListeningRemovals.shared
    @State private var shelf = AudiobookshelfBrowseService.shared
    @State private var player = AudiobookPlayer.shared
    /// Plex's books, the last read kept from the first frame.
    @State private var plex = PlexBookShelf.shared
    @State private var plexAuthenticator = PlexAuthenticator.shared

    private var showsPlex: Bool { coreFeatures.isEnabled(.plex) && hasPlexBooks }
    private var showsAudiobookshelf: Bool { coreFeatures.isEnabled(.audiobookshelf) && shelf.isAuthenticated }
    /// The Files folder's books (`FilesIndex`), on this device already.
    private var filesBooks: [PlayableContent] { coreFeatures.isEnabled(.files) ? FilesLibraryService.shared.books : [] }

    var body: some View {
        let _ = ScrollStopLog.note("body audiobooks")
        // Offline, only what's whole on this device plays.
        let isOffline = OfflineMode.shared.isActive
        let listened = isOffline ? listenedBooks.filter(AudiobookDownloads.isDownloaded) : listenedBooks
        let continuing = continuing(listened, isOffline: isOffline)
        let finished = listened.filter { store.progress(for: $0)?.isFinished == true }
        let downloaded = AudiobookDownloads.downloadedBooks(completeOnly: isOffline)
        // No server for books yet and none on this device: the tab asks
        // to sign in to one rather than showing empty shelves.
        let needsServer = !isOffline && !showsPlex && !showsAudiobookshelf
            && filesBooks.isEmpty && listened.isEmpty && downloaded.isEmpty

        NavigationStack(path: $router.path) {
            // A scroll view, not a list: a list gives each of its rows one
            // long-press menu, the first in it, so every book in the
            // Continue Listening card or a shelf brought up the first
            // book's menu.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !needsServer {
                        AudiobookContinueCard(books: continuing)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }

                    // On this device or on their way: what plays with no
                    // network.
                    if !downloaded.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            AudiobookSectionTitle(title: "Downloads", destination: .bookDownloads)
                            AudiobookCoverRow(books: downloaded)
                        }
                        .fontDesign(.rounded)
                    }

                    if !isOffline {
                        AudiobookSeriesSection(
                            plexBooks: showsPlex ? plex.all : [],
                            shelfSeries: showsAudiobookshelf ? shelf.series : []
                        )
                        AudiobookCollectionsSection(collections: showsAudiobookshelf ? shelf.collections : [])
                        libraries
                            .fontDesign(.rounded)
                    }

                    if !finished.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            AudiobookSectionTitle(title: "Finished")
                            ForEach(finished.prefix(Self.recentCount)) { book in
                                AudiobookFinishedRow(book: book)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                            }
                        }
                        .fontDesign(.rounded)
                    }

                    AudiobookWordsSection()
                }
            }
            .overlay {
                if needsServer {
                    serverPrompt
                }
            }
            // Rounded is set on each part rather than here: the outermost
            // `.fontDesign` wins, and the book's title is New York.
            .contentMargins(.bottom, 120, for: .scrollContent)
            .scrollStopLog("audiobooks")
            .navigationTitle("Audiobooks")
            // Inline, as the library tabs have it.
            .toolbarTitleDisplayMode(.inline)
            // Again for another Plex server, Plex's books turned on or
            // Audiobookshelf signed in while the tab is open (their sheets
            // over it).
            .task(id: "\(musicSearchService.plexServerID ?? "")|\(hasPlexBooks)|\(showsAudiobookshelf)") {
                await load()
            }
            // A pull scans each server, and reads it once the scan is done:
            // reading it at once as well read every server twice.
            .refreshable {
                scanServers()
            }
            .withAppRouter()
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }

    private static let recentCount = 10

    /// Every book not finished, started or only tried, as Audible has it,
    /// less those taken out of it and not listened to since
    /// (`ContinueListeningRemovals`). The book loaded to play leads even
    /// before a reading has come in (offline, only one downloaded: anything
    /// else won't play).
    private func continuing(_ listened: [PlayableContent], isOffline: Bool) -> [PlayableContent] {
        var books = listened.filter { store.progress(for: $0)?.isFinished != true }
        // Not one from a server signed out of, or switched off.
        let shown = loaded(fromShownServer: player.current?.book)
        if let loaded = shown, !isOffline || AudiobookDownloads.isDownloaded(loaded),
           store.progress(for: loaded)?.isFinished != true, !books.contains(where: { $0.isSameBook(as: loaded) }) {
            books.insert(loaded, at: 0)
        }
        return books.filter { !removals.isRemoved($0) }
    }

    /// `book`, when its server's books are shown.
    private func loaded(fromShownServer book: PlayableContent?) -> PlayableContent? {
        switch book?.content.service {
        case .plex: coreFeatures.isEnabled(.plex) ? book : nil
        case .audiobookshelf: showsAudiobookshelf ? book : nil
        case .files: coreFeatures.isEnabled(.files) ? book : nil
        default: nil
        }
    }

    /// Every book listened to, once each, newest first.
    private var listenedBooks: [PlayableContent] {
        AudiobookLibrary.listenedBooks(plex: coreFeatures.isEnabled(.plex), audiobookshelf: showsAudiobookshelf, files: coreFeatures.isEnabled(.files))
    }

    // MARK: - No server

    /// The tab before any server for books is set up: the way to one.
    /// Signed in to Plex already, what's missing is which of its libraries
    /// hold books, which the Plex sheet chooses too.
    private var serverPrompt: some View {
        let plexSignedIn = plexAuthenticator.authToken != nil
        return ContentUnavailableView {
            Label("No Audiobooks Yet", systemImage: "book")
        } description: {
            Text(plexSignedIn
                ? "Choose which of your Plex libraries hold books, or sign in to Audiobookshelf, to listen to them here."
                : "Sign in to Plex or Audiobookshelf to listen to your books here.")
        } actions: {
            VStack(spacing: 12) {
                Button {
                    router.presentedSheet = .plexManagement
                } label: {
                    Text(plexSignedIn ? "Choose Plex Books" : "Sign In to Plex")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    router.presentedSheet = .audiobookshelfManagement
                } label: {
                    Text("Sign In to Audiobookshelf")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.bordered)
            }
        }
        .fontDesign(.rounded)
    }

    // MARK: - Libraries

    /// A section for each server: its newest books as a row of covers, and
    /// the title opening every book it has.
    private var libraries: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsPlex {
                AudiobookSectionTitle(title: "Plex", destination: plexBooks, status: PlexBookScan.shared.status)
                if !plex.newest.isEmpty {
                    AudiobookCoverRow(books: plex.newest)
                } else if plex.failed {
                    plexUnreachable
                        .padding(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                } else if plex.isLoading {
                    // Plex's books are read whole, which takes a moment:
                    // their room is kept so the sections below don't move.
                    AudiobookCoverRowPlaceholder()
                }
            }
            if showsAudiobookshelf, let library = shelf.selectedLibrary {
                AudiobookSectionTitle(
                    title: LocalizedStringKey(shelf.libraries.count > 1 ? "Audiobookshelf · \(library.name)" : "Audiobookshelf"),
                    destination: audiobookshelfBooks(in: library),
                    status: shelf.isScanning ? "Scanning…" : nil
                )
                if !shelf.recentlyAdded.isEmpty {
                    AudiobookCoverRow(books: shelf.recentlyAdded)
                }
            }
            // The Files folder's books: an album with an .m4b in it, or
            // tagged as a book.
            let files = filesBooks
            if !files.isEmpty {
                AudiobookSectionTitle(title: "Files", destination: .playableList(
                    title: "Files",
                    showSectionIndex: false,
                    allowsGrid: true,
                    action: { offset in
                        guard offset == 0 else { return [] }
                        return files.map { $0.withAudiobookProgress(store.progress(for: $0)) }
                    }
                ))
                AudiobookCoverRow(books: files)
            }
        }
    }

    /// Plex's row when the server didn't answer.
    private var plexUnreachable: some View {
        HStack {
            Label("Couldn't reach Plex", systemImage: "wifi.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Try Again") {
                Task { await plex.read(tries: 1) }
            }
            .buttonStyle(.bordered)
            .font(.footnote.bold())
        }
    }

    /// Every Plex book, in the order picked.
    private var plexBooks: RouterDestination {
        .playableList(
            title: "Plex",
            showSectionIndex: false,
            allowsGrid: true,
            sortOptions: AudiobookLibrary.plexSortOptions,
            sortKey: "plex.books",
            // A pull has Plex scan for books added on the server.
            refreshAction: { await AudiobookLibrary.scanPlexBooks() },
            loadingStatus: { PlexBookScan.shared.status }
        )
    }

    /// Every book in the Audiobookshelf library, in the order picked.
    private func audiobookshelfBooks(in library: AudiobookshelfLibrary) -> RouterDestination {
        .playableList(
            title: library.name,
            showSectionIndex: false,
            allowsGrid: true,
            sortOptions: shelf.bookSortOptions,
            sortKey: "audiobookshelf.books",
            // A pull has the server scan for books added on it.
            refreshAction: { await shelf.scanAndRefresh() },
            searchAction: { query, offset in
                // The server answers a search in one go.
                guard offset == 0 else { return [] }
                return await shelf.search(query)
            },
            loadingStatus: { shelf.isScanning ? "Scanning…" : nil }
        )
    }

    // MARK: - Loading

    /// A pull has each server look through its folders for books added on
    /// it. That takes a while, so the pull doesn't wait: each server's
    /// title says it's scanning, and its books are read again once it's
    /// done.
    private func scanServers() {
        AudiobookLibrary.log.info("pull on the Audiobooks tab: scanning \(showsPlex ? "Plex " : "", privacy: .public)\(showsAudiobookshelf ? "Audiobookshelf" : "", privacy: .public)")
        if showsPlex {
            Task {
                await AudiobookLibrary.scanPlexBooks()
                await plex.read(tries: 1)
            }
        }
        if showsAudiobookshelf {
            Task { await shelf.scanAndRefresh() }
        }
    }

    /// The shelves as last read show at once (`ShelfCache`), and each
    /// server is read behind them, side by side, once while the app runs;
    /// again after a pull's scan (`scanServers()`).
    private func load() async {
        if coreFeatures.isEnabled(.plex) {
            // Another server's books aren't this one's: its own last read,
            // if one is kept.
            plex.show(server: musicSearchService.plexServerID)
            // Who reads each and the series it's in, from Audible, for the
            // books as last read; the read behind them asks for any new.
            AudiobookDetails.shared.request(plex.all)
        }
        async let shelfRead: Void = loadAudiobookshelf()
        async let plexRead: Void = loadPlex()
        _ = await (shelfRead, plexRead)
    }

    private func loadAudiobookshelf() async {
        guard showsAudiobookshelf, !shelf.hasLoaded else { return }
        await shelf.refresh()
    }

    private func loadPlex() async {
        guard coreFeatures.isEnabled(.plex) else { return }
        await AudiobookLibrary.checkPlexBooks()
        // Plex's books are read whole.
        if hasPlexBooks, !plex.isFresh {
            await plex.read(tries: 3)
        }
    }
}

// MARK: - Finished

/// A finished book: one link to its page, with its menu a long press away.
/// Not the list row (`AudiobookRow`): outside a list its Play button took
/// the tap, so a tap started the book again rather than opening it.
private struct AudiobookFinishedRow: View {
    let book: PlayableContent

    var body: some View {
        NavigationLink(value: RouterDestination.audiobookDetail(content: book)) {
            HStack(spacing: 14) {
                ContentArtworkView(content: book, showMusicSource: false, preferredSize: 160, cornerRadius: 6)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    // New York, a book's own face, for its title.
                    Text(book.title)
                        .font(.headline)
                        .fontDesign(.serif)
                        .lineLimit(2)
                    if !book.subtitle.isEmpty {
                        Text(book.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            AudiobookMenuItems(book: book)
        }
    }
}

// MARK: - Words

/// The words looked up last in any book, marked as Read Along marks them: a
/// tap shows a word's meaning again, held it offers Play from Here, and the
/// title opens every one (`BookWordsScreen`). A view of its own, so only it
/// redraws as words come and go.
private struct AudiobookWordsSection: View {
    @State private var lookups = BookWordLookups.shared

    var body: some View {
        let recent = lookups.recent(20)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                AudiobookSectionTitle(title: "Words", destination: .bookWords)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(recent) { item in
                            LookUpButton(term: item.lookup.term) {
                                Text(item.lookup.term)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(BookWordLabel.highlight, in: .capsule)
                                    .contentShape(.capsule)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                BookWordMenuItems(lookup: item.lookup, book: item.book)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
            .fontDesign(.rounded)
        }
    }
}

// MARK: - Continue Listening

/// A section's title, which scrolls away with its section; with a
/// `destination`, a chevron says the title opens it, and a `status` (a
/// server scanning) goes under it.
private struct AudiobookSectionTitle: View {
    let title: LocalizedStringKey
    var destination: RouterDestination?
    var status: String?

    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let destination {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    router.navigate(to: destination)
                } label: {
                    HStack {
                        Text(title)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else {
                Text(title)
            }
            if let status {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .font(.title3.bold())
        .accessibilityAddTraits(.isHeader)
        .animation(.default, value: status)
        .padding(EdgeInsets(top: 24, leading: 16, bottom: 6, trailing: 16))
    }
}

// MARK: - Series

/// Each series the servers have two or more books of, by name, as a row of
/// tiles: its first books' covers stacked, its name and how many books. A
/// tap opens its page (`AudiobookSeriesView`). A view of its own: Plex's
/// series come from what Audible says of each book (`AudiobookDetails`),
/// which fills in as the answers come, and only this redraws with it.
private struct AudiobookSeriesSection: View {
    let plexBooks: [PlayableContent]
    let shelfSeries: [AudiobookSeries]

    @Environment(Router.self) private var router

    /// The servers' series, one a name: a series on both is one tile.
    private var series: [AudiobookSeries] {
        let all = AudiobookLibrary.plexSeries(plexBooks) + shelfSeries
        return Dictionary(grouping: all) { $0.name.lowercased() }
            .compactMap { _, same in
                guard let first = same.first else { return nil }
                return AudiobookSeries(id: first.name.lowercased(), name: first.name, books: same.flatMap(\.books))
            }
            .filter { $0.books.count > 1 }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let series = series
        if !series.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                AudiobookSectionTitle(title: "Series")
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(series) { series in
                            Button {
                                HapticManager.shared.fireHaptic(.buttonPress)
                                router.navigate(to: .audiobookSeries(name: series.name, books: series.books))
                            } label: {
                                tile(series)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }
            .fontDesign(.rounded)
        }
    }

    private func tile(_ series: AudiobookSeries) -> some View {
        let narrations = AudiobookSeriesView.narrations(of: series.books)
        let lead = narrations.first?.books ?? series.books
        let count = narrations.map(\.books.count).max() ?? series.books.count
        let size = AudiobookCoverRow.coverSize
        return VStack(alignment: .leading, spacing: 4) {
            AudiobookCoverStack(books: lead, size: size)
            Text(series.name)
                .font(.footnote)
                .lineLimit(1)
            Text(narrations.count > 1 ? "^[\(count) book](inflect: true) · \(narrations.count) readings" : "^[\(count) book](inflect: true)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: size)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Collections

/// Audiobookshelf's collections, each a stack of its first covers with its
/// name, opening its books in the order they were put in it.
private struct AudiobookCollectionsSection: View {
    let collections: [AudiobookCollection]

    @Environment(Router.self) private var router

    var body: some View {
        if !collections.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                AudiobookSectionTitle(title: "Collections")
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(collections) { collection in
                            Button {
                                HapticManager.shared.fireHaptic(.buttonPress)
                                router.navigate(to: collection.destination)
                            } label: {
                                tile(collection)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }
            .fontDesign(.rounded)
        }
    }

    private func tile(_ collection: AudiobookCollection) -> some View {
        let size = AudiobookCoverRow.coverSize
        return VStack(alignment: .leading, spacing: 4) {
            AudiobookCoverStack(books: collection.books, size: size)
            Text(collection.name)
                .font(.footnote)
                .lineLimit(1)
            Text("^[\(collection.books.count) book](inflect: true)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: size)
    }
}
