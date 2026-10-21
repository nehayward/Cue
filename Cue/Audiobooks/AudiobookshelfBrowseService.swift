import Foundation
import MusicSearchKit
import Observation
import SonosKit

/// What the Audiobookshelf screen shows: the listener's book libraries, the
/// books they're partway through, and the chosen library's shelves.
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
    private(set) var continueListening: [PlayableContent] = []
    private(set) var recentlyAdded: [PlayableContent] = []
    private(set) var isLoading = false
    /// The last load couldn't reach the server.
    private(set) var failed = false

    private let api = AudiobookshelfAPI.shared

    private init() {}

    var isAuthenticated: Bool { api.isConfigured }

    /// The library the shelves are from: the one picked, else the server's
    /// default for this listener, else the first.
    var selectedLibrary: AudiobookshelfLibrary? {
        libraries.first { $0.id == api.defaultLibraryID } ?? libraries.first
    }

    func select(_ library: AudiobookshelfLibrary) {
        api.defaultLibraryID = library.id
        pages = [:]
        Task { await loadShelves() }
    }

    func load() async {
        guard isAuthenticated, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let libraries = await api.libraries() else {
            failed = true
            return
        }
        failed = false
        self.libraries = libraries
        await loadShelves()
    }

    func refresh() async {
        pages = [:]
        await load()
    }

    /// Forgets everything, for a sign-out.
    func clear() {
        libraries = []
        continueListening = []
        recentlyAdded = []
        pages = [:]
    }

    private func loadShelves() async {
        async let inProgress = api.itemsInProgress()
        async let progress = api.progressByItem()
        var recent: [PlayableContent] = []
        if let library = selectedLibrary,
           let page = await api.items(libraryID: library.id, page: 0, limit: 12, sort: "addedAt", descending: true) {
            recent = page.results.filter(\.hasAudio).map(\.toPlayable)
        }
        let store = AudiobookProgressStore.shared
        for (id, entry) in await progress ?? [:] {
            guard let reading = entry.audiobookProgress(duration: nil) else { continue }
            store.recordFromServer(reading, service: .audiobookshelf, id: id)
        }
        continueListening = (await inProgress ?? []).map(\.toPlayable)
        recentlyAdded = recent
    }

    // MARK: - Every book

    /// Which server page holds the books from each offset the list asks
    /// for. The list counts the rows it was given, and pages drop the
    /// library's ebooks, so an offset isn't a multiple of a page.
    private var pages: [Int: Int] = [0: 0]
    private static let pageSize = 50

    /// The books from `offset` on, in the selected library, by `sort` (a
    /// server sort key). Empty at the end.
    func books(offset: Int, sort: String = "media.metadata.title", descending: Bool = false) async -> [PlayableContent] {
        guard let library = selectedLibrary else { return [] }
        if offset == 0 { pages = [0: 0] }
        guard var page = pages[offset] else { return [] }
        // A page of nothing but ebooks isn't the end: carry on to the next.
        for _ in 0..<20 {
            guard let result = await api.items(libraryID: library.id, page: page, limit: Self.pageSize, sort: sort, descending: descending) else { return [] }
            let books = result.results.filter(\.hasAudio).map(\.toPlayable)
            let isLast = result.results.count < Self.pageSize || (result.total.map { (page + 1) * Self.pageSize >= $0 } ?? false)
            page += 1
            if !books.isEmpty {
                if !isLast { pages[offset + books.count] = page }
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
        [
            PlayableListSort(name: "Title") { offset, _ in
                await self.books(offset: offset, sort: "media.metadata.title")
            },
            PlayableListSort(name: "Author") { offset, _ in
                await self.books(offset: offset, sort: "media.metadata.authorNameLF")
            },
            PlayableListSort(name: "Recently Added") { offset, _ in
                await self.books(offset: offset, sort: "addedAt", descending: true)
            },
            PlayableListSort(name: "Length") { offset, _ in
                await self.books(offset: offset, sort: "media.duration", descending: true)
            }
        ]
    }

    /// Books matching `query` in the selected library.
    func search(_ query: String) async -> [PlayableContent] {
        guard let library = selectedLibrary else { return [] }
        return await api.search(libraryID: library.id, query: query).map(\.toPlayable)
    }

    /// The author called `name` in the selected library: their books, and
    /// their picture and biography when the server has them. Nil when
    /// there's no such author.
    func author(named name: String) async -> (books: [PlayableContent], image: URL?, about: String?)? {
        guard let library = selectedLibrary else { return nil }
        let match = await api.authors(libraryID: library.id, query: name)
            .first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        guard let match, let author = await api.author(id: match.id) else { return nil }
        let books = (author.libraryItems ?? []).filter(\.hasAudio).map(\.toPlayable)
        let image = author.imagePath == nil ? nil : AudiobookshelfAPI.authorImageURL(authorID: author.id)
        let about = author.description.map(AudiobookText.plain).flatMap { $0.isEmpty ? nil : $0 }
        return (books, image, about)
    }
}
