import Defaults
import Foundation
import MusicSearchKit
import Observation
import OSLog
import SonosKit
import UIKit
import WidgetKit

/// Keeps the book shelf widget's copy of the Audiobooks tab
/// (`BookShelfWidgetState`, in the App Group) current, each book's cover
/// written beside it, and asks WidgetKit to reload when it changes.
///
/// The shelves are the tab's own: Continue Listening as its card has it
/// (the book loaded on top, those taken out left out), the books finished,
/// those downloaded whole, and each server's newest. It follows the stores
/// they come from and writes a couple of seconds after the last change. A
/// book playing moves its place every few seconds, so a change of place
/// alone reaches the widget at most every `progressInterval`; anything else
/// (a book started, paused, finished, taken out, a cover landing) at once.
/// Leaving the foreground writes whatever's waiting, since the system may
/// suspend Cue before it would have.
///
/// It also answers the widget's links and Play (`book(withID:)`,
/// `play(bookID:)`), which name a book by its key: it keeps every book on
/// a shelf by key, in a file, so a widget tapped with Cue closed finds it.
///
/// `log stream --predicate 'subsystem == "dance.cue" AND category == "widgets"' --level debug`
@MainActor
final class BookShelfWidgetPublisher {
    static let shared = BookShelfWidgetPublisher()

    static let log = Logger(subsystem: "dance.cue", category: "widgets")

    /// Books kept on each shelf: as many as an extra large widget shows.
    static let shelfLimit = 12
    /// How often a playing book's place alone reaches the widget: each
    /// reload in the background counts against WidgetKit's daily budget.
    private static let progressInterval: TimeInterval = 5 * 60

    private var published: BookShelfWidgetState?
    private var lastPublished: Date = .distantPast
    private var isStarted = false
    private lazy var schedule = WidgetWriteSchedule { now in
        BookShelfWidgetPublisher.shared.publish(force: now)
    }
    private lazy var covers = WidgetCovers(folder: .books) {
        BookShelfWidgetPublisher.shared.schedule.after(.seconds(1))
    }
    /// Every book on a shelf, by key.
    private var books: [String: PlayableContent]?

    /// Every Audiobookshelf book, for the catalog (`Plex` keeps its own
    /// whole, `PlexBookShelf.all`), read now and then and kept in Caches.
    private lazy var audiobookshelfBooks: [PlayableContent] = ShelfCache.load([PlayableContent].self, named: Self.audiobookshelfCacheName) ?? []
    /// When Audiobookshelf's books were last read, or last failed to be (a
    /// failure waits `retryAfterFailure` rather than the whole interval);
    /// kept across launches, which come every few hours.
    private var audiobookshelfRead: Date = .distantPast
    private var audiobookshelfReading: Task<Void, Never>?
    private static let audiobookshelfCacheName = "BookShelfWidgetAudiobookshelf"
    private static let audiobookshelfReadName = "BookShelfWidgetAudiobookshelfRead"
    private static let everyBookInterval: TimeInterval = 6 * 3600
    private static let retryAfterFailure: TimeInterval = 30 * 60
    /// The catalog last written, and how many books it was made from, so
    /// a playing book's place moving doesn't sort every book again.
    private var catalog: BookShelfWidgetState.Catalog?
    private var catalogSourceCount = -1
    private var catalogWritten: Date = .distantPast
    /// The catalog's small covers, for Edit Widget's list.
    private let thumbnails = WidgetCatalogThumbnails(folder: .books)

    private init() {}

    /// Follows the stores from now on, and writes the shelves a moment
    /// after launch: a widget may still show a state an earlier Cue left.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        audiobookshelfRead = ShelfCache.load(Date.self, named: Self.audiobookshelfReadName) ?? .distantPast
        // Once each: each chain re-arms itself, and one started on every
        // re-arming piled up for good.
        schedule.follow({ BookShelfWidgetPublisher.shared.trackedState() }) {
            BookShelfWidgetPublisher.shared.schedule.after(.seconds(2))
        }
        // Places apart: a book playing keeps its place every couple of
        // seconds, and building the shelves that often, to write a place at
        // most every `progressInterval`, kept the main actor busy for
        // nothing. A place that moved is looked at within `placeDelay`,
        // unless something sooner is waiting.
        schedule.follow({ _ = AudiobookProgressStore.shared.readings }) {
            let schedule = BookShelfWidgetPublisher.shared.schedule
            if !schedule.isWaiting {
                schedule.after(Self.placeDelay)
            }
        }
        // As Cue comes back, Audiobookshelf's books for the catalog when due.
        schedule.start(firstAfter: .seconds(3)) {
            BookShelfWidgetPublisher.shared.readAudiobookshelfBooksIfDue()
        }
        readAudiobookshelfBooksIfDue()
    }

    /// Reads every Audiobookshelf book for the catalog, at most every
    /// `everyBookInterval`.
    private func readAudiobookshelfBooksIfDue() {
        guard Date.now.timeIntervalSince(audiobookshelfRead) > Self.everyBookInterval else { return }
        Task { await readAudiobookshelfBooks() }
    }

    private func readAudiobookshelfBooks() async {
        if let reading = audiobookshelfReading {
            await reading.value
            return
        }
        let service = AudiobookshelfBrowseService.shared
        // Not before its libraries are known: none read as no books, kept
        // for `everyBookInterval`.
        guard CoreFeatures.shared.isEnabled(.audiobookshelf), service.isAuthenticated, !service.libraries.isEmpty,
              !OfflineMode.shared.isActive else { return }
        let reading = Task {
            guard let books = await service.everyBook() else {
                // Not again at every write, a server out of reach answering
                // nothing each time.
                audiobookshelfRead = .now.addingTimeInterval(Self.retryAfterFailure - Self.everyBookInterval)
                ShelfCache.save(audiobookshelfRead, named: Self.audiobookshelfReadName)
                return
            }
            audiobookshelfRead = .now
            ShelfCache.save(audiobookshelfRead, named: Self.audiobookshelfReadName)
            audiobookshelfBooks = books
            ShelfCache.save(books, named: Self.audiobookshelfCacheName)
            Self.log.info("book shelf widget: \(books.count) Audiobookshelf books for the catalog")
            schedule.after(.seconds(1))
        }
        audiobookshelfReading = reading
        await reading.value
        audiobookshelfReading = nil
    }

    /// Writes the shelves now, place and all.
    func publishNow() {
        schedule.now()
    }

    // MARK: - Following

    private static let placeDelay: Duration = .seconds(30)

    /// Reads everything the shelves are made of but places, so the tracking
    /// registers on it.
    private func trackedState() {
        _ = PlayHistoryService.shared.history
        _ = ContinueListeningRemovals.shared.version
        let audiobookshelf = AudiobookshelfBrowseService.shared
        _ = audiobookshelf.continueListening
        _ = audiobookshelf.recentlyAdded
        _ = audiobookshelf.libraries
        _ = PlexBookShelf.shared.newest
        _ = PlexBookShelf.shared.all
        _ = PlexBookShelf.shared.hasBooks
        // A book landing or going, not its bytes coming down.
        _ = DownloadManager.shared.containerPresence
        let player = AudiobookPlayer.shared
        _ = player.current
        _ = player.currentChapter
        _ = PlaybackRoute.shared.presented.isPlaying
        // Where Play goes, shown beside it.
        _ = PlaybackRoute.shared.group?.nameWithCount
        _ = BookShelfWidgetState.Destination.thisDevice
        _ = OfflineMode.shared.isActive
        _ = CoreFeatures.shared.features
    }

    // MARK: - Writing

    private func publish(force: Bool) {
        let (state, contents) = makeState()
        // At the size `entry(for:)` names: a chosen book's is the lead's.
        covers.writeMissing(BookShelfWidgetState.Shelf.allCases.flatMap { shelf in
            state.books(on: shelf).enumerated().compactMap { index, book in
                contents[book.id].flatMap { coverSource(for: $0, key: book.id, isLead: index == 0 || shelf == .chosen) }
            }
        })
        remember(contents)
        writeCatalog(shelfBooks: contents, force: force)
        readAudiobookshelfBooksIfDue()
        guard state != published else { return }
        // Only the place moved: told now and then, unless Cue is leaving.
        let elapsed = Date.now.timeIntervalSince(lastPublished)
        if !force, let published, published.withoutPlaces == state.withoutPlaces, elapsed < Self.progressInterval {
            schedule.after(.seconds(Self.progressInterval - elapsed))
            return
        }
        do {
            try state.save()
        } catch {
            Self.log.error("book shelf widget: not written: \(error.localizedDescription, privacy: .public)")
            return
        }
        published = state
        lastPublished = .now
        WidgetCenter.shared.reloadTimelines(ofKind: BookShelfWidgetState.widgetKind)
        covers.removeAll(except: Set(BookShelfWidgetState.Shelf.allCases.flatMap { state.books(on: $0).compactMap(\.cover) }))
        let counts = BookShelfWidgetState.Shelf.allCases.map { "\($0.rawValue) \(state.books(on: $0).count)" }.joined(separator: ", ")
        Self.log.notice("book shelf widget: written (\(counts, privacy: .public)), playing \(state.isPlaying)")
    }

    /// The shelves as the Audiobooks tab shows them, and the books on them
    /// by key.
    private func makeState() -> (BookShelfWidgetState, [String: PlayableContent]) {
        let features = CoreFeatures.shared
        let audiobookshelf = AudiobookshelfBrowseService.shared
        let plex = PlexBookShelf.shared
        let store = AudiobookProgressStore.shared
        let player = AudiobookPlayer.shared
        let isOffline = OfflineMode.shared.isActive
        let plexOn = features.isEnabled(.plex)
        let showsPlex = plexOn && plex.hasBooks
        let showsAudiobookshelf = features.isEnabled(.audiobookshelf) && audiobookshelf.isAuthenticated
        let filesOn = features.isEnabled(.files)

        // Offline, only what's whole on this device plays.
        var listened = AudiobookLibrary.listenedBooks(plex: plexOn, audiobookshelf: showsAudiobookshelf, files: filesOn)
        if isOffline {
            listened = listened.filter(AudiobookDownloads.isDownloaded)
        }
        // `AudiobooksScreen.continuing`: the book loaded leads even before a
        // reading has come in.
        var continuing = listened.filter { store.progress(for: $0)?.isFinished != true }
        if let loaded = player.current?.book, isShown(loaded, plex: plexOn, audiobookshelf: showsAudiobookshelf, files: filesOn),
           !isOffline || AudiobookDownloads.isDownloaded(loaded),
           store.progress(for: loaded)?.isFinished != true, !continuing.contains(where: { $0.isSameBook(as: loaded) }) {
            continuing.insert(loaded, at: 0)
        }
        let removals = ContinueListeningRemovals.shared
        continuing = continuing.filter { !removals.isRemoved($0) }
        let finished = listened.filter { store.progress(for: $0)?.isFinished == true }
        let downloaded = AudiobookDownloads.downloadedBooks(completeOnly: true)
        let recentlyAdded = isOffline ? [] : (showsPlex ? plex.newest : []) + (showsAudiobookshelf ? audiobookshelf.recentlyAdded : [])
        let filesBooks = filesOn ? FilesLibraryService.shared.books : []
        let needsServer = !isOffline && !showsPlex && !showsAudiobookshelf && filesBooks.isEmpty && listened.isEmpty && downloaded.isEmpty

        // The books widgets are set to (One Book), from wherever Cue has them.
        let chosen = BookShelfWidgetState.chosenBookIDs().sorted().compactMap(book(withID:))

        var contents: [String: PlayableContent] = [:]
        var shelves: [String: [BookShelfWidgetState.Book]] = [:]
        for (shelf, books) in [
            (BookShelfWidgetState.Shelf.continueListening, continuing),
            (.recentlyAdded, recentlyAdded),
            (.downloaded, downloaded),
            (.finished, finished),
            (.chosen, chosen),
        ] {
            var seen: Set<String> = []
            var entries: [BookShelfWidgetState.Book] = []
            for book in books {
                let key = AudiobookProgressStore.key(for: book)
                // Every chosen book: each One Book widget picks its own, and
                // one cut by the limit lost its place and cover.
                guard shelf == .chosen || entries.count < Self.shelfLimit, seen.insert(key).inserted else { continue }
                contents[key] = book
                // A chosen book is shown on its own, at the lead's size.
                entries.append(entry(for: book, key: key, isLead: entries.isEmpty || shelf == .chosen))
            }
            shelves[shelf.rawValue] = entries
        }

        // The book loaded, while the player is on it.
        let presented = PlaybackRoute.shared.presented
        let loaded = player.isPlayingBook(on: presented) ? player.current?.book : nil
        let state = BookShelfWidgetState(
            shelves: shelves,
            loadedID: loaded.map(AudiobookProgressStore.key(for:)),
            isPlaying: loaded != nil && presented.isPlaying,
            chapter: loaded != nil && player.hasChapters ? player.currentChapter?.title : nil,
            needsServer: needsServer,
            speaker: PlaybackRoute.shared.group?.nameWithCount,
            device: .thisDevice
        )
        return (state, contents)
    }

    /// Writes the catalog Edit Widget's Book offers (`WidgetBookQuery`):
    /// the shelves' books, those listened to and downloaded, and every book
    /// of each server shown. Made only when their count has changed, or
    /// ten minutes on, or as Cue leaves.
    private func writeCatalog(shelfBooks: [String: PlayableContent], force: Bool) {
        let features = CoreFeatures.shared
        let plexOn = features.isEnabled(.plex)
        let showsAudiobookshelf = features.isEnabled(.audiobookshelf) && AudiobookshelfBrowseService.shared.isAuthenticated
        let filesOn = features.isEnabled(.files)
        let plexAll = plexOn && PlexBookShelf.shared.hasBooks ? PlexBookShelf.shared.all : []
        let audiobookshelfAll = showsAudiobookshelf && !OfflineMode.shared.isActive ? audiobookshelfBooks : []
        let listened = AudiobookLibrary.listenedBooks(plex: plexOn, audiobookshelf: showsAudiobookshelf, files: filesOn)
        let downloaded = AudiobookDownloads.downloadedBooks(completeOnly: true)
        let files = filesOn ? FilesLibraryService.shared.books : []
        let count = shelfBooks.count + plexAll.count + audiobookshelfAll.count + listened.count + downloaded.count + files.count
        guard force || count != catalogSourceCount || Date.now.timeIntervalSince(catalogWritten) > 10 * 60 else { return }
        let everyBook = Array(shelfBooks.values) + listened + downloaded + files + plexAll + audiobookshelfAll
        catalogSourceCount = count
        catalogWritten = .now
        var seen: Set<String> = []
        var unique: [(key: String, book: PlayableContent)] = []
        let books = everyBook.compactMap { book -> BookShelfWidgetState.Book? in
            let key = AudiobookProgressStore.key(for: book)
            guard seen.insert(key).inserted else { return nil }
            unique.append((key, book))
            return BookShelfWidgetState.Book(id: key, title: book.title, author: book.subtitle, fraction: nil, remaining: nil, duration: 0, isFinished: false, isDownloaded: false, cover: nil)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        thumbnails.writeMissing(for: unique.map { ($0.key, $0.book) })
        let catalog = BookShelfWidgetState.Catalog(books: books)
        guard catalog != self.catalog else { return }
        self.catalog = catalog
        Task.detached(priority: .utility) {
            try? catalog.save()
        }
        Self.log.info("book shelf widget: catalog of \(books.count) books")
    }

    /// Whether `book`'s server's books are shown.
    private func isShown(_ book: PlayableContent, plex: Bool, audiobookshelf: Bool, files: Bool) -> Bool {
        switch book.content.service {
        case .plex: plex
        case .audiobookshelf: audiobookshelf
        case .files: files
        default: false
        }
    }

    private func entry(for book: PlayableContent, key: String, isLead: Bool) -> BookShelfWidgetState.Book {
        let progress = AudiobookProgressStore.shared.progress(for: book)
        // The cover at this size, else one written before until it is.
        let cover = covers.file(for: coverSource(for: book, key: key, isLead: isLead), key: key)
        return BookShelfWidgetState.Book(
            id: key,
            title: book.title,
            author: book.subtitle,
            fraction: progress?.fraction,
            remaining: progress.flatMap { $0.isStarted && $0.duration > 0 ? $0.remaining : nil },
            duration: progress?.duration ?? 0,
            isFinished: progress?.isFinished == true,
            isDownloaded: DownloadManager.shared.containerPresence(for: book) == .downloaded,
            cover: cover
        )
    }

    // MARK: - Covers

    /// `book`'s cover at the widget's size: its Audible edition's, as on
    /// the phone. Nil for a book with no cover.
    private func coverSource(for book: PlayableContent, key: String, isLead: Bool) -> WidgetCovers.Source? {
        WidgetCovers.source(for: ContentArtworkView.drawnContent(for: book), key: key, isLead: isLead)
    }

    // MARK: - The widget's books

    private static var booksURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BookShelfWidgetBooks.json")
    }

    /// Keeps the books on the shelves by key, in a file when they change.
    private func remember(_ contents: [String: PlayableContent]) {
        var known = books ?? Self.loadBooks()
        let before = known
        known.merge(contents) { _, new in new }
        // Only what's on a shelf now, and what was on one last time: a
        // widget can still show a book for a moment after it leaves.
        let kept = Set(contents.keys).union(published.map { state in
            BookShelfWidgetState.Shelf.allCases.flatMap { state.books(on: $0).map(\.id) }
        } ?? [])
        known = known.filter { kept.contains($0.key) }
        books = known
        guard known != before, let url = Self.booksURL, let data = try? JSONEncoder().encode(known) else { return }
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func loadBooks() -> [String: PlayableContent] {
        guard let url = booksURL, let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: PlayableContent].self, from: data)) ?? [:]
    }

    /// The book a widget names by its key, from the shelves last written,
    /// else wherever the app knows it from.
    func book(withID id: String) -> PlayableContent? {
        if books == nil {
            books = Self.loadBooks()
        }
        if let book = books?[id] { return book }
        var candidates: [PlayableContent] = []
        if let loaded = AudiobookPlayer.shared.current?.book {
            candidates.append(loaded)
        }
        candidates += PlayHistoryService.shared.history.filter { $0.content.type == .audiobook }
        candidates += AudiobookshelfBrowseService.shared.continueListening
        candidates += AudiobookDownloads.downloadedBooks()
        // One Book's, which may be any book on a server.
        candidates += PlexBookShelf.shared.all
        candidates += audiobookshelfBooks
        candidates += FilesLibraryService.shared.books
        return candidates.first { AudiobookProgressStore.key(for: $0) == id }
    }

    /// `book(withID:)`, else once Audiobookshelf's books are read: a book
    /// chosen in Edit Widget and tapped before Cue has heard of it.
    func findBook(withID id: String) async -> PlayableContent? {
        if let book = book(withID: id) { return book }
        // Only for one of its books, and not again within ten minutes: a
        // book gone from a server shouldn't read the library each tap.
        guard id.hasPrefix(AudiobookProgressStore.key(service: .audiobookshelf, id: "")),
              Date.now.timeIntervalSince(audiobookshelfRead) > 10 * 60 else { return nil }
        await readAudiobookshelfBooks()
        return book(withID: id)
    }

    /// The widget's `cue://audiobook` link: the book's page in the
    /// Audiobooks tab (Open Book), or with `plays` (Play Book with Play in
    /// Background off), the player, and the widget's Play or Pause done in
    /// it (`playOrPause`). A book the widget knows and Cue no longer does
    /// opens the tab.
    func open(bookID: String, plays: Bool) async {
        guard let book = await findBook(withID: bookID) else {
            Self.log.error("book shelf widget: no book \(bookID, privacy: .public) to open")
            Router.showAudiobooks()
            return
        }
        Self.log.notice("book shelf widget: \(plays ? "open playing" : "open", privacy: .public) \(book.title, privacy: .public)")
        guard plays else {
            Router.showAudiobooks(book)
            return
        }
        MediaDetailPresenter.dismissPresented()
        // Cue is in front already; the player opens with the Play, after
        // asking where when nothing plays.
        await playOrPause(book, bringForward: { true }, opensPlayer: true)
    }

    /// The widget's Play, as Continue Listening's Play does. The widget is
    /// written again before it returns, so its reload after the intent
    /// shows the book as it is. With nothing playing, a book not loaded asks
    /// where first, once `bringForward` has brought Cue to the front
    /// (`WidgetPlayChoice`).
    func play(bookID: String, bringForward: (@MainActor () async -> Bool)? = nil) async {
        guard let book = await findBook(withID: bookID) else {
            Self.log.error("book shelf widget: no book \(bookID, privacy: .public) to play")
            return
        }
        await playOrPause(book, bringForward: bringForward)
        publishNow()
    }

    /// The book loaded plays or pauses where it is; any other starts from
    /// where it was left, where the route points. The speakers are looked
    /// for first, so a book a speaker plays reads as loaded after a launch
    /// in the background (before, the phone's parked queue read as it, and
    /// Pause started it on the phone). Then it waits for the player to say
    /// so, 3 s at most: written at once, the widget kept the state before
    /// the change, and Cue, woken for this alone, could be suspended before
    /// a book on a parked queue began (its Play starts it in a task).
    private func playOrPause(_ book: PlayableContent, bringForward: (@MainActor () async -> Bool)? = nil, opensPlayer: Bool = false) async {
        await PlayDestinationRouter.loadSpeakersIfNeeded()
        let player = AudiobookPlayer.shared
        let expected: Bool
        if player.isLoaded(book) {
            expected = !PlaybackRoute.shared.presented.isPlaying
            Self.log.notice("book shelf widget: \(expected ? "play" : "pause", privacy: .public) \(book.title, privacy: .public)")
            if opensPlayer {
                Router.main.isPlayerPresented = true
            }
            await PlaybackRoute.shared.presented.togglePlayback()
        } else {
            if let bringForward {
                switch await WidgetPlayChoice.ask(about: book, bringForward: bringForward) {
                case .cancelled:
                    return
                case .chosen:
                    Router.main.isPlayerPresented = true
                case .notAsked:
                    break
                }
            }
            if opensPlayer {
                Router.main.isPlayerPresented = true
            }
            expected = true
            Self.log.notice("book shelf widget: play \(book.title, privacy: .public)")
            await player.play(book)
        }
        for _ in 0..<12 where PlaybackRoute.shared.presented.isPlaying != expected {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}

private extension BookShelfWidgetState {
    /// The same shelves with no places in them, to tell a book that moved on
    /// from anything else changing.
    var withoutPlaces: BookShelfWidgetState {
        var copy = self
        copy.shelves = shelves.mapValues { books in
            books.map { book in
                var book = book
                book.fraction = nil
                book.remaining = nil
                return book
            }
        }
        return copy
    }
}
