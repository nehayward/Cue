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
        let chosen = chosenAudiobookLibraryKeys
        return await getMusicLibraries()
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

    /// Whether the selected server has any books to show: a library kept
    /// for them, or an audiobook genre in the music library.
    public func hasAudiobooks() async -> Bool {
        if !(await audiobookLibraries()).isEmpty { return true }
        guard includesGenreTaggedAudiobooks, let music = librarySelectionID,
              let server = await getPlexServer(), let base = getBaseURL(for: server) else { return false }
        return !(await audiobookGenres(sectionKey: music, base: base)).isEmpty
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

        let libraries = await audiobookLibraries()
        var sources: [(path: String, query: [URLQueryItem])] = libraries.map {
            ("/library/sections/\($0.key)/all", [])
        }
        if includesGenreTaggedAudiobooks,
           let music = librarySelectionID,
           !libraries.contains(where: { $0.key == music }) {
            for genre in await audiobookGenres(sectionKey: music, base: base) {
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

    /// The music library's album genres that mark books.
    private func audiobookGenres(sectionKey: String, base: URL) async -> [PlexDirectoryItem] {
        var url = base.appending(path: "/library/sections/\(sectionKey)/genre")
        url.append(queryItems: [URLQueryItem(name: "type", value: "\(PlexMediaType.album.rawValue)")])
        let container: PlexContainer<PlexDirectoryContainer>? = await loadAuthorized(url)
        return container?.mediaContainer.directory?.filter { PlexAudiobookRules.isAudiobookGenre($0.title) } ?? []
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

    /// A book's files in playing order, with their stream URLs, where each
    /// was left, and the chapter marks inside them. Plex lists chapters
    /// only on an item's own metadata, so a book of a few files (an `.m4b`,
    /// or one per CD) is read again with `includeChapters=1`; a book of
    /// many files is a file per chapter, and the files are its chapters.
    public func audiobookParts(ratingKey: String) async -> [PlexMetadata]? {
        guard let server = await getPlexServer(),
              let base = getBaseURL(for: server) else { return nil }
        let childrenURL = base.appending(path: "/library/metadata/\(ratingKey)/children")
        guard let container: PlexContainer<PlexMetadataList> = await loadAuthorized(childrenURL) else { return nil }
        var parts = container.mediaContainer.metadata ?? []
        if !parts.isEmpty, parts.count <= Self.chapterLookupLimit {
            var url = base.appending(path: "/library/metadata/\(parts.map(\.ratingKey).joined(separator: ","))")
            url.append(queryItems: [URLQueryItem(name: "includeChapters", value: "1")])
            let detailed: PlexContainer<PlexMetadataList>? = await loadAuthorized(url)
            let byKey = Dictionary(
                (detailed?.mediaContainer.metadata ?? []).map { ($0.ratingKey, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            // The detailed copy where there is one, in the children's order.
            parts = parts.map { byKey[$0.ratingKey] ?? $0 }
        }
        return await enrichMetadata(metadata: parts)
    }

    /// Up to this many files, a book is read again for its chapter marks.
    private static let chapterLookupLimit = 8

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
