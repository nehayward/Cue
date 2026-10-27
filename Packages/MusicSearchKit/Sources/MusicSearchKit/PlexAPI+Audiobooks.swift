import Foundation

/// Audiobooks on the selected Plex server: the Music libraries kept for
/// books, and books kept in the music library under an audiobook genre
/// (see `PlexAudiobookRules`).
///
/// A book is an album; its tracks are its files. Plex keeps where each
/// file was left (`viewOffset`) from the timeline reports Cue already sends
/// while it plays, and counts a file played once a report carries it past
/// the end, so the place in a book follows the listener between Cue and
/// any other Plex player.
extension PlexAPI {
    // MARK: - Which libraries hold books

    /// A Music library on the selected server, and whether its albums are
    /// read as books.
    public struct AudiobookLibrary: Identifiable {
        public let section: PlexLibrarySection
        public let isBooks: Bool
        public var id: String { section.key }

        public init(section: PlexLibrarySection, isBooks: Bool) {
            self.section = section
            self.isBooks = isBooks
        }
    }

    private static func audiobookLibrariesKey(serverID: String) -> String {
        "com.cue.plexServer.audiobookLibraries.\(serverID)"
    }

    /// The keys of the libraries chosen as books on the selected server, or
    /// nil while the listener hasn't chosen: then the libraries that look
    /// like books are used (`PlexAudiobookRules.looksLikeAudiobooks`). Kept
    /// per server, so switching server starts from its own suggestions.
    public var chosenAudiobookLibraryKeys: [String]? {
        get {
            guard let serverID else { return nil }
            return UserDefaults.standard.stringArray(forKey: Self.audiobookLibrariesKey(serverID: serverID))
        }
        set {
            guard let serverID else { return }
            UserDefaults.standard.set(newValue, forKey: Self.audiobookLibrariesKey(serverID: serverID))
        }
    }

    /// Whether books tagged with an audiobook genre in the music library
    /// show with the rest. On unless turned off.
    public var includesGenreTaggedAudiobooks: Bool {
        get { UserDefaults.standard.object(forKey: "com.cue.plexServer.genreTaggedAudiobooks") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "com.cue.plexServer.genreTaggedAudiobooks") }
    }

    /// Every Music library on the selected server but the one chosen for
    /// music, with whether it's read as books.
    public func audiobookLibraryChoices() async -> [AudiobookLibrary] {
        audiobookLibraryChoices(from: await getMusicLibraries())
    }

    /// `libraries` but the one chosen for music, with whether each is read
    /// as books.
    private func audiobookLibraryChoices(from libraries: [PlexLibrarySection]) -> [AudiobookLibrary] {
        let chosen = chosenAudiobookLibraryKeys
        return libraries
            .filter { $0.key != librarySelectionID }
            .map { section in
                let isBooks = chosen.map { $0.contains(section.key) }
                    ?? PlexAudiobookRules.looksLikeAudiobooks(title: section.title, agent: section.agent)
                return AudiobookLibrary(section: section, isBooks: isBooks)
            }
    }

    /// The libraries whose albums are books.
    public func audiobookLibraries() async -> [PlexLibrarySection] {
        await audiobookLibraryChoices().filter(\.isBooks).map(\.section)
    }

    private static func knownAudiobookLibrariesKey(serverID: String) -> String {
        "com.cue.plexServer.knownAudiobookLibraries.\(serverID)"
    }

    /// The keys of the libraries whose albums are books, read from the
    /// server, or as last read when it doesn't answer: search sorts what it
    /// finds by them, and a server that's slow to list its libraries
    /// shouldn't turn books back into albums.
    public func audiobookLibraryKeys() async -> Set<String> {
        guard let sections = await musicLibraries() else { return knownAudiobookLibraryKeys }
        let keys = Set(audiobookLibraryChoices(from: sections).filter(\.isBooks).map(\.section.key))
        knownAudiobookLibraryKeys = keys
        return keys
    }

    /// The book libraries' keys as `audiobookLibraryKeys()` last read them,
    /// for a check that can't wait on the server (an artist page deciding
    /// whether it's an author's). Kept per server.
    public internal(set) var knownAudiobookLibraryKeys: Set<String> {
        get {
            guard let serverID else { return [] }
            return Set(UserDefaults.standard.stringArray(forKey: Self.knownAudiobookLibrariesKey(serverID: serverID)) ?? [])
        }
        set {
            guard let serverID else { return }
            UserDefaults.standard.set(newValue.sorted(), forKey: Self.knownAudiobookLibrariesKey(serverID: serverID))
        }
    }

    /// Whether the selected server has any books to show: a library kept
    /// for them, or an audiobook genre in the music library.
    public func hasAudiobooks() async -> Bool {
        if !(await audiobookLibraries()).isEmpty { return true }
        guard includesGenreTaggedAudiobooks, let music = librarySelectionID,
              let server = await getPlexServer(), let base = getBaseURL(for: server) else { return false }
        return !(await audiobookGenres(sectionKey: music, base: base) ?? []).isEmpty
    }

    // MARK: - Books

    /// Every book, sorted by title: the albums of the book libraries, then
    /// the music library's albums under an audiobook genre. Read whole, a
    /// page of 200 at a time and 5,000 at most from each source: there are
    /// several sources to merge, and a shelf of books is small beside a
    /// music library. Nil when the server couldn't be read, so a failed
    /// refresh doesn't empty a shelf that was there.
    public func audiobooks() async -> [PlexAudiobookItem]? {
        guard let server = await getPlexServer(),
              let token = server.accessToken,
              let clientID = server.clientIdentifier,
              let base = getBaseURL(for: server) else { return nil }

        // A listing that failed isn't a server without books: nil, not a
        // shelf read as empty.
        guard let sections = await musicLibraries() else { return nil }
        let libraries = audiobookLibraryChoices(from: sections).filter(\.isBooks).map(\.section)
        var sources: [(path: String, query: [URLQueryItem])] = libraries.map {
            ("/library/sections/\($0.key)/all", [])
        }
        if includesGenreTaggedAudiobooks,
           let music = librarySelectionID,
           sections.contains(where: { $0.key == music }),
           !libraries.contains(where: { $0.key == music }) {
            guard let genres = await audiobookGenres(sectionKey: music, base: base) else { return nil }
            for genre in genres {
                sources.append(("/library/sections/\(music)/all", [URLQueryItem(name: "genre", value: genre.key)]))
            }
        }

        var books: [PlexAudiobookItem] = []
        var seen = Set<String>()
        for source in sources {
            guard let page = await allAlbums(base: base, path: source.path, query: source.query) else { return nil }
            for book in page where seen.insert(book.ratingKey).inserted {
                books.append(decorated(book, base: base, token: token, clientID: clientID))
            }
        }
        return books.sorted {
            ($0.titleSort ?? $0.title).localizedStandardCompare($1.titleSort ?? $1.title) == .orderedAscending
        }
    }

    /// The music library's album genres that mark books; nil when they
    /// couldn't be read.
    private func audiobookGenres(sectionKey: String, base: URL) async -> [PlexDirectoryItem]? {
        var url = base.appending(path: "/library/sections/\(sectionKey)/genre")
        url.append(queryItems: [URLQueryItem(name: "type", value: "\(PlexMediaType.album.rawValue)")])
        guard let container: PlexContainer<PlexDirectoryContainer> = await loadAuthorized(url) else { return nil }
        return container.mediaContainer.directory?.filter { PlexAudiobookRules.isAudiobookGenre($0.title) } ?? []
    }

    private static let audiobookPageSize = 200
    private static let audiobookPageLimit = 25

    /// Every album under `path`, page by page. Nil if a page fails, so a
    /// half-read shelf isn't taken for the whole.
    private func allAlbums(base: URL, path: String, query: [URLQueryItem]) async -> [PlexAudiobookItem]? {
        var albums: [PlexAudiobookItem] = []
        for page in 0..<Self.audiobookPageLimit {
            var url = base.appending(path: path)
            url.append(queryItems: query + [
                URLQueryItem(name: "type", value: "\(PlexMediaType.album.rawValue)"),
                URLQueryItem(name: "sort", value: "titleSort:asc"),
                URLQueryItem(name: "X-Plex-Container-Start", value: "\(page * Self.audiobookPageSize)"),
                URLQueryItem(name: "X-Plex-Container-Size", value: "\(Self.audiobookPageSize)")
            ])
            guard let container: PlexContainer<PlexAudiobookContainer> = await loadAuthorized(url) else { return nil }
            let items = container.mediaContainer.metadata ?? []
            albums += items
            let total = container.mediaContainer.totalSize ?? Int.max
            if items.count < Self.audiobookPageSize || albums.count >= total { break }
        }
        return albums
    }

    /// One author's books in a library kept for books: their artist's
    /// albums (`artistKey`, a book's `parentRatingKey`), in one request
    /// rather than the whole shelf read to pick theirs out. Nil when the
    /// server couldn't be read, or the artist is in a library that isn't
    /// for books (the music library, where only albums under an audiobook
    /// genre are books, which the artist's list doesn't say): the caller
    /// reads the shelf then.
    public func audiobooks(byArtist artistKey: String) async -> [PlexAudiobookItem]? {
        guard let server = await getPlexServer(),
              let token = server.accessToken,
              let clientID = server.clientIdentifier,
              let base = getBaseURL(for: server) else { return nil }
        let url = base.appending(path: "/library/metadata/\(artistKey)/children")
        guard let container: PlexContainer<PlexAudiobookContainer> = await loadAuthorized(url) else { return nil }
        let albums = container.mediaContainer.metadata ?? []
        let bookLibraries = Set(await audiobookLibraries().map(\.key))
        let section = (albums.first?.librarySectionID ?? container.mediaContainer.librarySectionID).map(String.init)
        guard let section, bookLibraries.contains(section) else { return nil }
        return albums.map { decorated($0, base: base, token: token, clientID: clientID) }
    }

    /// One book by its rating key, for a book opened from history or a
    /// link rather than the shelf.
    public func audiobook(ratingKey: String) async -> PlexAudiobookItem? {
        guard let server = await getPlexServer(),
              let token = server.accessToken,
              let clientID = server.clientIdentifier,
              let base = getBaseURL(for: server) else { return nil }
        let url = base.appending(path: "/library/metadata/\(ratingKey)")
        let container: PlexContainer<PlexAudiobookContainer>? = await loadAuthorized(url)
        guard let book = container?.mediaContainer.metadata?.first else { return nil }
        return decorated(book, base: base, token: token, clientID: clientID)
    }

    private func decorated(_ book: PlexAudiobookItem, base: URL, token: String, clientID: String) -> PlexAudiobookItem {
        var book = book
        book.sonosID = "\(clientID)%3A3%3A\(book.ratingKey)"
        if let thumb = book.thumb {
            book.thumbImageURL = base
                .appending(path: thumb)
                .appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
        }
        return book
    }

    // MARK: - A book's files

    /// A book's files in playing order, with their stream URLs and where
    /// each was left. Their chapter marks come on their own
    /// (`audiobookChapterMarks(parts:)`).
    public func audiobookParts(ratingKey: String) async -> [PlexMetadata]? {
        guard let server = await getPlexServer(),
              let base = getBaseURL(for: server) else { return nil }
        let childrenURL = base.appending(path: "/library/metadata/\(ratingKey)/children")
            .appending(queryItems: [URLQueryItem(name: "includeChapters", value: "1")])
        guard let container: PlexContainer<PlexMetadataList> = await loadAuthorized(childrenURL) else { return nil }
        return await enrichMetadata(metadata: container.mediaContainer.metadata ?? [])
    }

    /// The chapter marks inside a book's files (an `.m4b`'s), by each
    /// file's rating key; a file with none is left out. Plex lists them
    /// only on a file's own metadata with `includeChapters=1`, so each file
    /// is asked on its own, and read for nothing but its marks: a whole
    /// track's metadata that didn't decode lost them before. A book of many
    /// files is a file per chapter, and isn't asked.
    public func audiobookChapterMarks(parts: [PlexMetadata]) async -> [String: [AudiobookChapterMark]] {
        guard !parts.isEmpty, parts.count <= Self.chapterLookupLimit,
              let server = await getPlexServer(),
              let base = getBaseURL(for: server) else { return [:] }
        return await withTaskGroup(of: (String, [AudiobookChapterMark]).self) { group in
            for part in parts {
                group.addTask {
                    let url = base.appending(path: "/library/metadata/\(part.ratingKey)")
                        .appending(queryItems: [URLQueryItem(name: "includeChapters", value: "1")])
                    let container: PlexContainer<PlexChapterLookup>? = await self.loadAuthorized(url)
                    let chapters = container?.mediaContainer.metadata?.first?.chapters ?? []
                    return (part.ratingKey, PlexAudiobook.chapterMarks(chapters))
                }
            }
            var marks: [String: [AudiobookChapterMark]] = [:]
            for await (key, found) in group where !found.isEmpty {
                marks[key] = found
            }
            return marks
        }
    }

    /// Up to this many files, a book's files are asked for chapter marks.
    public static let chapterLookupLimit = 8

    // MARK: - Scanning

    /// Asks the server to scan the libraries with `keys` for files added,
    /// changed or gone, as Plex's own Scan Library Files does. True when it
    /// started at least one; only the server's owner may. Asked straight
    /// rather than through `loadAuthorized`, which takes a 401 for a sign-in
    /// gone bad and signs out: here it's only a listener who isn't the
    /// owner.
    public func scan(sectionKeys keys: [String]) async -> Bool {
        guard let server = await getPlexServer(),
              let token = server.accessToken,
              let base = getBaseURL(for: server) else { return false }
        var started = false
        for key in keys {
            var request = URLRequest(url: base.appending(path: "/library/sections/\(key)/refresh"))
            request.timeoutInterval = 10
            request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
            request.addValue(token, forHTTPHeaderField: "X-Plex-Token")
            guard let (_, response) = await loadData(for: request),
                  let status = (response as? HTTPURLResponse)?.statusCode else { continue }
            if (200...299).contains(status) {
                started = true
            }
        }
        return started
    }

    /// Whether the server is scanning any of the libraries with `keys`; nil
    /// when it couldn't be asked.
    public func isScanning(sectionKeys keys: [String]) async -> Bool? {
        let libraries = await getMusicLibraries()
        guard !libraries.isEmpty else { return nil }
        return libraries.contains { keys.contains($0.key) && $0.refreshing == true }
    }

    // MARK: - Played state

    /// Marks a book (or one file) played, or unplayed — which also forgets
    /// where it was left. Marking an album marks all its files.
    @discardableResult
    public func markPlayed(ratingKey: String, _ played: Bool) async -> Bool {
        guard let server = await getPlexServer(),
              let token = server.accessToken,
              var url = getBaseURL(for: server)?.appending(path: played ? ":/scrobble" : ":/unscrobble") else { return false }
        url.append(queryItems: [
            URLQueryItem(name: "key", value: ratingKey),
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library")
        ])
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.addValue("Cue", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")
        guard let (_, response) = await loadData(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }
}
