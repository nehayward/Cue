import Defaults
import Foundation
import MusicSearchKit
import Nuke
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

    private static let log = Logger(subsystem: "dance.cue", category: "widgets")

    /// Books kept on each shelf: as many as an extra large widget shows.
    static let shelfLimit = 12
    /// The cover sizes written, as `ContentArtworkView` asks for them (a
    /// third of the pixels): a shelf's first book, which the small widget
    /// and the large one's lead show bigger, and the rest.
    private static let leadCoverPoints: Double = 200
    private static let coverPoints: Double = 100
    /// How often a playing book's place alone reaches the widget: each
    /// reload in the background counts against WidgetKit's daily budget.
    private static let progressInterval: TimeInterval = 5 * 60

    private var published: BookShelfWidgetState?
    private var lastPublished: Date = .distantPast
    private var pending: Task<Void, Never>?
    private var isStarted = false
    /// The covers in the widget's folder, by file name.
    private lazy var writtenCovers: Set<String> = {
        let files = BookShelfWidgetState.directory.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
        return Set(files.filter { $0.hasSuffix(".jpg") })
    }()
    /// The covers being fetched and written, by file name.
    private var coversUnderWay: Set<String> = []
    /// When each cover that didn't load was last tried: a playing book
    /// writes the shelves every few seconds, and an unreachable server
    /// shouldn't be asked every time.
    private var coverFailures: [String: Date] = [:]
    private static let coverRetryInterval: TimeInterval = 10 * 60
    /// Every book on a shelf, by key.
    private var books: [String: PlayableContent]?
    private var backgroundObserver: (any NSObjectProtocol)?

    private init() {}

    /// Follows the stores from now on, and writes the shelves a moment
    /// after launch: a widget may still show a state an earlier Cue left.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        observe()
        schedule(after: .seconds(3))
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                BookShelfWidgetPublisher.shared.publishNow()
            }
        }
    }

    /// Writes the shelves now, place and all.
    func publishNow() {
        pending?.cancel()
        pending = nil
        publish(force: true)
    }

    // MARK: - Following

    /// Re-arms after every change, the same shape as CarPlay's `observe()`.
    private func observe() {
        withObservationTracking {
            trackedState()
        } onChange: {
            Task { @MainActor in
                let publisher = BookShelfWidgetPublisher.shared
                publisher.schedule(after: .seconds(2))
                publisher.observe()
            }
        }
    }

    /// Reads everything the shelves are made of, so the tracking registers
    /// on it.
    private func trackedState() {
        _ = AudiobookProgressStore.shared.readings
        _ = PlayHistoryService.shared.history
        _ = ContinueListeningRemovals.shared.version
        let audiobookshelf = AudiobookshelfBrowseService.shared
        _ = audiobookshelf.continueListening
        _ = audiobookshelf.recentlyAdded
        _ = PlexBookShelf.shared.newest
        _ = PlexBookShelf.shared.hasBooks
        // A book landing or going, not its bytes coming down.
        _ = DownloadManager.shared.containerPresence
        let player = AudiobookPlayer.shared
        _ = player.current
        _ = player.currentChapter
        _ = PlaybackRoute.shared.presented.isPlaying
        _ = OfflineMode.shared.isActive
        _ = CoreFeatures.shared.features
    }

    private func schedule(after delay: Duration) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            pending = nil
            publish(force: false)
        }
    }

    // MARK: - Writing

    private func publish(force: Bool) {
        let (state, contents) = makeState()
        writeCoversMissing(from: contents, in: state)
        remember(contents)
        guard state != published else { return }
        // Only the place moved: told now and then, unless Cue is leaving.
        let elapsed = Date.now.timeIntervalSince(lastPublished)
        if !force, let published, published.withoutPlaces == state.withoutPlaces, elapsed < Self.progressInterval {
            schedule(after: .seconds(Self.progressInterval - elapsed))
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
        removeUnusedCovers(keeping: state)
        let counts = BookShelfWidgetState.Shelf.allCases.map { "\($0.rawValue) \(state.books(on: $0).count)" }.joined(separator: ", ")
        Self.log.info("book shelf widget: written (\(counts, privacy: .public)), playing \(state.isPlaying)")
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

        var contents: [String: PlayableContent] = [:]
        var shelves: [String: [BookShelfWidgetState.Book]] = [:]
        for (shelf, books) in [
            (BookShelfWidgetState.Shelf.continueListening, continuing),
            (.recentlyAdded, recentlyAdded),
            (.downloaded, downloaded),
            (.finished, finished),
        ] {
            var seen: Set<String> = []
            var entries: [BookShelfWidgetState.Book] = []
            for book in books {
                let key = AudiobookProgressStore.key(for: book)
                guard entries.count < Self.shelfLimit, seen.insert(key).inserted else { continue }
                contents[key] = book
                entries.append(entry(for: book, key: key, isLead: entries.isEmpty))
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
            needsServer: needsServer
        )
        return (state, contents)
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
        // The cover at this size, else one written before (another size, a
        // cover since replaced) until it is.
        let cover = coverSource(for: book, isLead: isLead).flatMap { source in
            writtenCovers.contains(source.name) ? source.name : writtenCovers.first { $0.hasPrefix(BookShelfWidgetState.coverPrefix(for: key)) }
        }
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

    /// The request for `book`'s cover at the widget's size, and the file
    /// it's written to. Nil for a book with no cover.
    private func coverSource(for book: PlayableContent, isLead: Bool) -> (name: String, request: ImageRequest)? {
        // A book shows its Audible edition's cover, as on the phone.
        let drawn = ContentArtworkView.drawnContent(for: book)
        guard let url = drawn.artwork ?? drawn.thumbnail else { return nil }
        let points = isLead ? Self.leadCoverPoints : Self.coverPoints
        let request = ContentArtworkView.artworkRequest(for: drawn, url: url, preferredSize: points)
        let pixels = Int(ContentArtworkView.maxPixelSize(for: points))
        let name = BookShelfWidgetState.coverName(for: AudiobookProgressStore.key(for: book), source: url.absoluteString, pixels: pixels)
        return (name, request)
    }

    /// Fetches and writes the covers the shelves have no file for at their
    /// size yet, and writes the shelves again once one lands.
    private func writeCoversMissing(from contents: [String: PlayableContent], in state: BookShelfWidgetState) {
        for shelf in BookShelfWidgetState.Shelf.allCases {
            for (index, book) in state.books(on: shelf).enumerated() {
                guard let content = contents[book.id], let source = coverSource(for: content, isLead: index == 0),
                      !writtenCovers.contains(source.name), !coversUnderWay.contains(source.name),
                      Date.now.timeIntervalSince(coverFailures[source.name] ?? .distantPast) > Self.coverRetryInterval else { continue }
                coversUnderWay.insert(source.name)
                Task {
                    let written = await Self.writeCover(source.request, named: source.name)
                    coversUnderWay.remove(source.name)
                    guard written else {
                        coverFailures[source.name] = .now
                        return
                    }
                    coverFailures[source.name] = nil
                    writtenCovers.insert(source.name)
                    schedule(after: .seconds(1))
                }
            }
        }
    }

    /// Fetches `request` (the phone's own cache first) and writes it as a
    /// JPEG. False when it didn't load or wasn't written.
    private static func writeCover(_ request: ImageRequest, named name: String) async -> Bool {
        guard let image = try? await ImagePipeline.shared.image(for: request),
              let url = BookShelfWidgetState.coverURL(named: name) else { return false }
        return await Task.detached(priority: .utility) {
            guard let data = image.jpegData(compressionQuality: 0.85) else { return false }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return (try? data.write(to: url, options: .atomic)) != nil
        }.value
    }

    /// Takes away the covers no shelf names any more. One on its way isn't
    /// named yet, and isn't in `writtenCovers` until it's written.
    private func removeUnusedCovers(keeping state: BookShelfWidgetState) {
        guard let directory = BookShelfWidgetState.directory else { return }
        let named = Set(BookShelfWidgetState.Shelf.allCases.flatMap { state.books(on: $0).compactMap(\.cover) })
        for name in writtenCovers where !named.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            writtenCovers.remove(name)
        }
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
        let candidates = [AudiobookPlayer.shared.current?.book].compactMap { $0 }
            + Array(PlayHistoryService.shared.history).filter { $0.content.type == .audiobook }
            + AudiobookshelfBrowseService.shared.continueListening
            + AudiobookDownloads.downloadedBooks()
        return candidates.first { AudiobookProgressStore.key(for: $0) == id }
    }

    /// The widget's Play: the book loaded plays or pauses where it is, any
    /// other starts from where it was left, where the route points, as
    /// Continue Listening's Play does. The widget is written again before
    /// it returns, so its reload after the intent shows the book playing.
    func play(bookID: String) async {
        guard let book = book(withID: bookID) else {
            Self.log.error("book shelf widget: no book \(bookID, privacy: .public) to play")
            return
        }
        let player = AudiobookPlayer.shared
        if player.isLoaded(book) {
            Self.log.notice("book shelf widget: play/pause \(book.title, privacy: .public)")
            await PlaybackRoute.shared.presented.togglePlayback()
        } else {
            Self.log.notice("book shelf widget: play \(book.title, privacy: .public)")
            await player.play(book)
        }
        publishNow()
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
