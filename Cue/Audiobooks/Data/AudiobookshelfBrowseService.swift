import Foundation
import MusicSearchKit
import Observation
import SonosKit

/// What the Audiobookshelf screen shows: the listener's book libraries, the
/// books they're partway through, and the chosen library's shelves; and
/// beside the books, the podcast libraries and their newest episodes. An
/// episode plays as a book of one file (`AudiobookshelfMediaKey`), so it
/// sits in Continue Listening with the books.
///
/// The server's place in every book is copied into
/// `AudiobookProgressStore` as it loads, where it wins only if it's newer
/// than this device's — so the rows' progress lines show what another
/// player did meanwhile.
@MainActor
@Observable
final class AudiobookshelfBrowseService {
    static let shared = AudiobookshelfBrowseService()

    private(set) var libraries: [AudiobookshelfLibrary] = []
    /// The podcast libraries, which the book shelves leave out.
    private(set) var podcastLibraries: [AudiobookshelfLibrary] = []
    /// The newest episodes across the podcast libraries, newest first.
    private(set) var latestEpisodes: [PlayableContent] = []
    private(set) var continueListening: [PlayableContent] = []
    private(set) var recentlyAdded: [PlayableContent] = []
    private(set) var isLoading = false
    /// The last load couldn't reach the server.
    private(set) var failed = false

    /// Read from the server since launch (the shelves show the last read
    /// kept until then).
    private(set) var hasLoaded = false

    private let api = AudiobookshelfAPI.shared

    /// The shelves as last read, in Caches (`ShelfCache`), so they show at
    /// once at launch while the server is read behind them.
    private struct Snapshot: Codable, Sendable {
        let libraries: [AudiobookshelfLibrary]
        let continueListening: [PlayableContent]
        let recentlyAdded: [PlayableContent]
        let series: [AudiobookSeries]
        // Optional, so a snapshot kept before podcasts still reads.
        let podcastLibraries: [AudiobookshelfLibrary]?
        let latestEpisodes: [PlayableContent]?
    }

    private static let cacheName = "Audiobookshelf"

    private init() {
        guard api.isConfigured, let kept = ShelfCache.load(Snapshot.self, named: Self.cacheName) else { return }
        libraries = kept.libraries
        continueListening = kept.continueListening
        recentlyAdded = kept.recentlyAdded
        series = kept.series
        podcastLibraries = kept.podcastLibraries ?? []
        latestEpisodes = kept.latestEpisodes ?? []
    }

    private func keep() {
        ShelfCache.save(Snapshot(
            libraries: libraries,
            continueListening: continueListening,
            recentlyAdded: recentlyAdded,
            series: series,
            podcastLibraries: podcastLibraries,
            latestEpisodes: latestEpisodes
        ), named: Self.cacheName)
    }

    var isAuthenticated: Bool { api.isConfigured }

    /// The library the shelves are from: the one picked, else the server's
    /// default for this listener, else the first.
    var selectedLibrary: AudiobookshelfLibrary? {
        libraries.first { $0.id == api.defaultLibraryID } ?? libraries.first
    }

    func select(_ library: AudiobookshelfLibrary) {
        api.defaultLibraryID = library.id
        Task { await loadShelves() }
    }

    func load() async {
        guard isAuthenticated, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let all = await api.allLibraries() else {
            failed = true
            return
        }
        failed = false
        libraries = all.filter(\.isBooks)
        podcastLibraries = all.filter(\.isPodcasts)
        await loadShelves()
        hasLoaded = true
    }

    func refresh() async {
        pages = [:]
        await load()
    }

    /// While the server scans the selected library for books added on it,
    /// after a pull on the Audiobooks tab.
    private(set) var isScanning = false

    /// Has the server scan the selected library, waits for it to finish
    /// (as `PlexBookScan` does, 30 s at most), then reads the books again.
    /// Only an admin may start a scan: for anyone else this just reads.
    func scanAndRefresh() async {
        if let library = selectedLibrary, !isScanning, await api.scan(libraryID: library.id) {
            isScanning = true
            AudiobookLibrary.log.info("audiobookshelf scan of \(library.name, privacy: .public) started")
            let clock = ContinuousClock()
            let start = clock.now
            // The scan shows among the server's tasks a moment after it's
            // asked for, so the first look comes after a wait.
            while clock.now - start < .seconds(30) {
                try? await Task.sleep(for: .seconds(2))
                guard await api.isScanning(libraryID: library.id) == true else { break }
            }
            isScanning = false
            AudiobookLibrary.log.info("audiobookshelf scan of \(library.name, privacy: .public) done or left after \((clock.now - start).formatted(.units(allowed: [.seconds])), privacy: .public)")
        }
        await refresh()
    }

    /// Forgets everything, for a sign-out.
    func clear() {
        libraries = []
        podcastLibraries = []
        latestEpisodes = []
        continueListening = []
        recentlyAdded = []
        series = []
        pages = [:]
        hasLoaded = false
        ShelfCache.save(Optional<Snapshot>.none, named: Self.cacheName)
    }

    private func loadShelves() async {
        let withEpisodes = !podcastLibraries.isEmpty
        async let inProgress = api.itemsInProgress(includingEpisodes: withEpisodes)
        async let progress = api.progressByItem()
        async let episodes = newestEpisodes()
        var recent: [PlayableContent] = []
        if let library = selectedLibrary,
           let page = await api.items(libraryID: library.id, page: 0, limit: 12, sort: "addedAt", descending: true) {
            recent = rows(from: page.results)
        }
        let store = AudiobookProgressStore.shared
        for (id, entry) in await progress ?? [:] {
            guard let reading = entry.audiobookProgress(duration: nil) else { continue }
            store.recordFromServer(reading, service: .audiobookshelf, id: id)
        }
        continueListening = rows(from: await inProgress ?? [])
        recentlyAdded = recent
        if let episodes = await episodes {
            latestEpisodes = episodes
        }
        if let library = selectedLibrary, let found = await api.series(libraryID: library.id) {
            series = found.compactMap { entry in
                let books = rows(from: entry.books ?? [])
                return books.isEmpty ? nil : AudiobookSeries(id: "audiobookshelf|\(entry.id)", name: entry.name, books: books)
            }
        }
        keep()
    }

    /// The library's series with books to listen to, each in its order.
    private(set) var series: [AudiobookSeries] = []

    // MARK: - Podcasts

    private static let latestEpisodeCount = 12

    /// The newest episodes of every podcast library, newest first; nil when
    /// none could be read, so a failed read keeps the shelf as it was.
    private func newestEpisodes() async -> [PlayableContent]? {
        guard !podcastLibraries.isEmpty else { return [] }
        var episodes: [AudiobookshelfItem] = []
        var answered = false
        for library in podcastLibraries {
            guard let found = await api.recentEpisodes(libraryID: library.id, limit: Self.latestEpisodeCount) else { continue }
            answered = true
            episodes += found
        }
        guard answered else { return nil }
        let newest = episodes.sorted { ($0.addedAt ?? 0) > ($1.addedAt ?? 0) }.prefix(Self.latestEpisodeCount)
        return rows(from: Array(newest))
    }

    /// The podcasts in `library`, by title.
    func podcasts(in library: AudiobookshelfLibrary) async -> [AudiobookshelfPodcast]? {
        var podcasts: [AudiobookshelfPodcast] = []
        for page in 0..<20 {
            guard let result = await api.items(libraryID: library.id, page: page, limit: Self.pageSize) else {
                return page == 0 ? nil : podcasts
            }
            podcasts += result.results.filter(\.isPodcast).map(AudiobookshelfPodcast.init)
            let isLast = result.results.count < Self.pageSize || (result.total.map { (page + 1) * Self.pageSize >= $0 } ?? false)
            if isLast { break }
        }
        return podcasts
    }

    /// Podcasts matching `query` in every podcast library.
    func searchPodcasts(_ query: String) async -> [AudiobookshelfPodcast] {
        var found: [AudiobookshelfPodcast] = []
        for library in podcastLibraries {
            found += await api.searchPodcasts(libraryID: library.id, query: query).filter(\.isPodcast).map(AudiobookshelfPodcast.init)
        }
        return found
    }

    /// A podcast read whole: what it is, and its episodes newest first,
    /// each with what's left of it. Nil when it couldn't be read.
    func podcast(id: String) async -> (podcast: AudiobookshelfPodcast, episodes: [PlayableContent])? {
        guard let item = await api.podcast(id: id) else { return nil }
        let episodes = rows(from: api.episodes(of: item))
        return (
            AudiobookshelfPodcast(item),
            episodes.map { $0.withAudiobookProgress(AudiobookProgressStore.shared.progress(for: $0)) }
        )
    }

    /// `items`' books, as rows: who reads each and its series noted
    /// (`AudiobookDetails`), ebooks left out.
    private func rows(from items: [AudiobookshelfItem]) -> [PlayableContent] {
        let books = items.filter(\.hasAudio)
        AudiobookDetails.shared.note(books.filter { !$0.isEpisode })
        let rows = books.map(\.toPlayable)
        // Audible, for any the server names no reader for.
        AudiobookDetails.shared.request(rows)
        return rows
    }

    // MARK: - Every book

    /// Which server page holds the books from each offset a list asks for,
    /// by library and order: the list counts the rows it was given, and
    /// pages drop the library's ebooks, so an offset isn't a multiple of a
    /// page. Each order has its own, so two lists open at once (the Library
    /// tab's and the Audiobooks tab's, or CarPlay's) don't read each
    /// other's, and one starting over doesn't cut another short.
    private var pages: [String: [Int: Int]] = [:]
    private static let pageSize = 50

    /// The books from `offset` on, in the selected library, by `sort` (a
    /// server sort key). Empty at the end.
    func books(offset: Int, sort: String = "media.metadata.title", descending: Bool = false) async -> [PlayableContent] {
        guard let library = selectedLibrary else { return [] }
        let order = "\(library.id)|\(sort)|\(descending)"
        guard var page = offset == 0 ? 0 : pages[order]?[offset] else { return [] }
        // A page of nothing but ebooks isn't the end: carry on to the next.
        for _ in 0..<20 {
            guard let result = await api.items(libraryID: library.id, page: page, limit: Self.pageSize, sort: sort, descending: descending) else { return [] }
            let books = rows(from: result.results)
            let isLast = result.results.count < Self.pageSize || (result.total.map { (page + 1) * Self.pageSize >= $0 } ?? false)
            page += 1
            if !books.isEmpty {
                if !isLast { pages[order, default: [:]][offset + books.count] = page }
                return books.map { $0.withAudiobookProgress(AudiobookProgressStore.shared.progress(for: $0)) }
            }
            if isLast { return [] }
        }
        return []
    }

    /// The All Books list's orders, each its own loader. The server sorts,
    /// so each pages through in its own order and there's no direction to
    /// flip, as for Subsonic's albums.
    var bookSortOptions: [PlayableListSort] {
        // Audible's orders, each the server's own, so the list pages in.
        // Recent Activity is when this account's place in a book last moved.
        [
            PlayableListSort(name: "Recent Activity") { offset, _ in
                await self.books(offset: offset, sort: "progress", descending: true)
            },
            PlayableListSort(name: "Title", ascendingLabel: "A–Z", descendingLabel: "Z–A") { offset, descending in
                await self.books(offset: offset, sort: "media.metadata.title", descending: descending)
            },
            PlayableListSort(name: "Author", ascendingLabel: "A–Z", descendingLabel: "Z–A") { offset, descending in
                await self.books(offset: offset, sort: "media.metadata.authorNameLF", descending: descending)
            },
            PlayableListSort(name: "Length", ascendingLabel: "Short to Long", descendingLabel: "Long to Short") { offset, descending in
                await self.books(offset: offset, sort: "media.duration", descending: descending)
            },
            PlayableListSort(name: "Release Date", ascendingLabel: "Old to New", descendingLabel: "New to Old", defaultsToDescending: true) { offset, descending in
                await self.books(offset: offset, sort: "media.metadata.publishedYear", descending: descending)
            },
            PlayableListSort(name: "Date Added", ascendingLabel: "Old to New", descendingLabel: "New to Old", defaultsToDescending: true) { offset, descending in
                await self.books(offset: offset, sort: "addedAt", descending: descending)
            }
        ]
    }

    /// The selected library, reading the server's list first when nothing
    /// has yet: a page opened from the player before the Audiobooks tab.
    private func loadedLibrary() async -> AudiobookshelfLibrary? {
        if libraries.isEmpty, isAuthenticated, let fetched = await api.libraries() {
            libraries = fetched
        }
        return selectedLibrary
    }

    /// Books matching `query` in the selected library.
    func search(_ query: String) async -> [PlayableContent] {
        guard let library = await loadedLibrary() else { return [] }
        return rows(from: await api.search(libraryID: library.id, query: query))
    }

    /// The author called `name`: their books, and their picture and
    /// biography when the server has them. In the selected library first,
    /// then the others, which a book from Continue Listening can be in. Nil
    /// when there's no such author.
    func author(named name: String) async -> (books: [PlayableContent], image: URL?, about: String?)? {
        guard let selected = await loadedLibrary() else { return nil }
        var match: AudiobookshelfAuthor?
        for library in [selected] + libraries.filter({ $0.id != selected.id }) {
            match = await api.authors(libraryID: library.id, query: name)
                .first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            if match != nil { break }
        }
        guard let match, let author = await api.author(id: match.id) else { return nil }
        let books = rows(from: author.libraryItems ?? [])
        let image = author.imagePath == nil ? nil : AudiobookshelfAPI.authorImageURL(authorID: author.id)
        let about = author.description.map(AudiobookText.plain).flatMap { $0.isEmpty ? nil : $0 }
        return (books, image, about)
    }
}
