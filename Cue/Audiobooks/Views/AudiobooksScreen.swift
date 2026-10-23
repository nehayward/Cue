import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// The Audiobooks tab: Continue Listening, the books not yet finished with
/// the one listened to last on top, each one tap from where it was left;
/// the books on this device; a section for each server, its newest books
/// with the way to every one; and what was finished lately.
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
    @State private var shelf = AudiobookshelfBrowseService.shared
    @State private var player = AudiobookPlayer.shared
    /// Plex's newest books, for its section's row, and the server they're
    /// from.
    @State private var plexPreview: [PlayableContent] = []
    @State private var plexPreviewServer: String?
    /// From the first frame: the row keeps its room while Plex is first
    /// asked whether it has books, before its books are read.
    @State private var isLoadingPlex = true
    /// Plex didn't answer after a few tries: the row offers another.
    @State private var plexFailed = false

    private var showsPlex: Bool { coreFeatures.isEnabled(.plex) && hasPlexBooks }
    private var showsAudiobookshelf: Bool { coreFeatures.isEnabled(.audiobookshelf) && shelf.isAuthenticated }

    var body: some View {
        // Offline, only what's whole on this device plays.
        let isOffline = OfflineMode.shared.isActive
        let listened = isOffline ? listenedBooks.filter(AudiobookDownloads.isDownloaded) : listenedBooks
        let continuing = continuing(listened, isOffline: isOffline)
        let finished = listened.filter { store.progress(for: $0)?.isFinished == true }
        let downloaded = AudiobookDownloads.downloadedBooks(completeOnly: isOffline)

        NavigationStack(path: $router.path) {
            List {
                AudiobookContinueCard(books: continuing)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)

                // On this device or on their way: what plays with no network.
                if !downloaded.isEmpty {
                    Section {
                        AudiobookSectionTitle(title: "Downloads", destination: .bookDownloads)
                        AudiobookCoverRow(books: downloaded)
                            .listRowInsets(EdgeInsets())
                    }
                    .fontDesign(.rounded)
                    .listRowSeparator(.hidden)
                }

                if !isOffline {
                    libraries
                        .fontDesign(.rounded)
                }

                if !finished.isEmpty {
                    Section {
                        AudiobookSectionTitle(title: "Finished")
                        ForEach(finished.prefix(Self.recentCount)) { book in
                            AudiobookRow(book: book)
                        }
                    }
                    .fontDesign(.rounded)
                    .listRowInsets(.default)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            // Rounded is set on each part rather than here: the outermost
            // `.fontDesign` wins, and the book's title is New York.
            .contentMargins(.bottom, 120, for: .scrollContent)
            .navigationTitle("Audiobooks")
            // Again for another Plex server, or Plex's books turned on
            // while the tab is open (the Plex sheet over it).
            .task(id: "\(musicSearchService.plexServerID ?? "")|\(hasPlexBooks)") {
                await load()
            }
            .refreshable {
                await load(refreshing: true)
            }
            .miniPlayerOnScrollHandler()
            .withAppRouter()
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }

    private static let recentCount = 10

    /// Every book not finished, started or only tried, as Audible has it.
    /// The book loaded to play leads even before a reading has come in
    /// (offline, only one downloaded: anything else won't play).
    private func continuing(_ listened: [PlayableContent], isOffline: Bool) -> [PlayableContent] {
        var books = listened.filter { store.progress(for: $0)?.isFinished != true }
        // Not one from a server signed out of, or switched off.
        let shown = loaded(fromShownServer: player.current?.book)
        if let loaded = shown, !isOffline || AudiobookDownloads.isDownloaded(loaded),
           store.progress(for: loaded)?.isFinished != true, !books.contains(where: { $0.isSameBook(as: loaded) }) {
            books.insert(loaded, at: 0)
        }
        return books
    }

    /// `book`, when its server's books are shown.
    private func loaded(fromShownServer book: PlayableContent?) -> PlayableContent? {
        switch book?.content.service {
        case .plex: coreFeatures.isEnabled(.plex) ? book : nil
        case .audiobookshelf: showsAudiobookshelf ? book : nil
        default: nil
        }
    }

    /// Every book listened to, once each, newest first.
    private var listenedBooks: [PlayableContent] {
        AudiobookLibrary.listenedBooks(plex: coreFeatures.isEnabled(.plex), audiobookshelf: showsAudiobookshelf)
    }

    // MARK: - Libraries

    /// A section for each server: its newest books as a row of covers, and
    /// the title opening every book it has.
    @ViewBuilder
    private var libraries: some View {
        if showsPlex {
            Section {
                AudiobookSectionTitle(title: "Plex", destination: plexBooks)
                if !plexPreview.isEmpty {
                    AudiobookCoverRow(books: plexPreview)
                        .listRowInsets(EdgeInsets())
                } else if plexFailed {
                    plexUnreachable
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                } else if isLoadingPlex {
                    // Plex's books are read whole, which takes a moment:
                    // their room is kept so the sections below don't move.
                    AudiobookCoverRowPlaceholder()
                        .listRowInsets(EdgeInsets())
                }
            }
            .listRowSeparator(.hidden)
        }
        if showsAudiobookshelf, let library = shelf.selectedLibrary {
            Section {
                AudiobookSectionTitle(
                    title: LocalizedStringKey(shelf.libraries.count > 1 ? "Audiobookshelf · \(library.name)" : "Audiobookshelf"),
                    destination: audiobookshelfBooks(in: library)
                )
                if !shelf.recentlyAdded.isEmpty {
                    AudiobookCoverRow(books: shelf.recentlyAdded)
                        .listRowInsets(EdgeInsets())
                }
            }
            .listRowSeparator(.hidden)
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
                Task { await loadPlexPreview(tries: 1) }
            }
            .buttonStyle(.bordered)
            .font(.footnote.bold())
        }
    }

    /// Every Plex book, by title.
    private var plexBooks: RouterDestination {
        .playableList(
            title: "Plex",
            showSectionIndex: false,
            allowsGrid: true,
            // A pull has Plex scan for books added on the server.
            refreshAction: { await AudiobookLibrary.scanPlexBooks() },
            loadingStatus: { PlexBookScan.shared.status },
            action: { offset in
                // Read whole: the shelf merges several sources.
                guard offset == 0 else { return [] }
                return await AudiobookLibrary.plexShelf()
            }
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
            searchAction: { query, offset in
                // The server answers a search in one go.
                guard offset == 0 else { return [] }
                return await shelf.search(query)
            }
        )
    }

    // MARK: - Loading

    private func load(refreshing: Bool = false) async {
        if showsAudiobookshelf {
            if refreshing || shelf.libraries.isEmpty {
                await shelf.refresh()
            }
        }
        if coreFeatures.isEnabled(.plex) {
            await AudiobookLibrary.checkPlexBooks()
            // Another server's books aren't this one's.
            let server = musicSearchService.plexServerID
            if server != plexPreviewServer {
                plexPreview = []
                plexPreviewServer = server
            }
            // Once a launch, and on a pull: Plex's books are read whole.
            // A pull is waited on, so it asks once.
            if hasPlexBooks, refreshing || plexPreview.isEmpty {
                await loadPlexPreview(tries: refreshing ? 1 : 3)
            }
        }
    }

    /// Plex's newest books, for its row. A read that fails is tried again
    /// after a pause: as the tab first shows, the server's connection is
    /// often still being found, and one miss then left the row empty until
    /// a pull. What's shown stays when every try fails.
    private func loadPlexPreview(tries: Int) async {
        isLoadingPlex = true
        plexFailed = false
        for attempt in 1...tries {
            let newest = await AudiobookLibrary.plexNewestBooks()
            // Put away (another server, the tab left): a cancelled read
            // fails or comes back short, and isn't the answer.
            guard !Task.isCancelled else { return }
            if let newest {
                plexPreview = newest
                isLoadingPlex = false
                return
            }
            AudiobookLibrary.log.info("plex shelf: newest books not read, try \(attempt) of \(tries)")
            if attempt < tries {
                guard (try? await Task.sleep(for: .seconds(2 * attempt))) != nil else { return }
            }
        }
        isLoadingPlex = false
        plexFailed = true
    }
}

// MARK: - Continue Listening

/// A section's title, as its first row rather than its header: a plain
/// list pins a header to the top while its section scrolls under it, and
/// these scroll away with their section. Drawn as the list's prominent
/// header was; with a `destination`, a chevron says the title opens it.
private struct AudiobookSectionTitle: View {
    let title: LocalizedStringKey
    var destination: RouterDestination?

    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading) {
            if let destination {
                // A button, not a link: a link in a plain list draws its
                // own disclosure arrow, small and grey.
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
        }
        .font(.title3.bold())
        .accessibilityAddTraits(.isHeader)
        .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
    }
}
