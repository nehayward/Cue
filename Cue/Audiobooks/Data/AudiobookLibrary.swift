import Defaults
import Foundation
import MusicSearchKit
import OSLog
import SonosKit

/// Books from the servers that keep them: the shelves, and a book read
/// whole — its files, chapters and where it was left — ready to play.
@MainActor
enum AudiobookLibrary {
    static let log = Logger(subsystem: "dance.cue", category: "audiobooks")

    // MARK: - Shelves

    /// Every Plex book: the libraries kept for books, and the music
    /// library's albums under an audiobook genre. Nil when the server
    /// couldn't be read.
    static func plexBooks() async -> [PlayableContent]? {
        guard let books = await PlexAPI.shared.audiobooks() else { return nil }
        return books.compactMap(\.toPlayable)
    }

    /// The books of a Plex author, by their artist's rating key: the
    /// artist's albums when it's in a library kept for books, else every
    /// book read and theirs kept (`isTheirs`), for an author whose books
    /// are genre-tagged albums in the music library.
    static func plexBooks(byArtist artistKey: String, isTheirs: (PlayableContent) -> Bool) async -> [PlayableContent] {
        if let books = await PlexAPI.shared.audiobooks(byArtist: artistKey) {
            log.info("plex author \(artistKey, privacy: .public): \(books.count) books from the artist's albums")
            return books.compactMap(\.toPlayable)
        }
        let books = (await plexBooks() ?? []).filter(isTheirs)
        log.info("plex author \(artistKey, privacy: .public): not in a book library; \(books.count) books from the whole shelf")
        return books
    }

    /// The Plex shelf's rows: every book, with what's left of each in its
    /// subtitle. Plex's own reading of where each book is comes only with
    /// the book's files, so this is this device's.
    static func plexShelf() async -> [PlayableContent] {
        await plexShelf(by: .title, descending: false)
    }

    /// Plex's every-book list's orders. Read whole (the shelf merges
    /// several sources), so a list's first page is all of it.
    static var plexSortOptions: [PlayableListSort] {
        func sort(_ order: PlexOrder) -> (Int, Bool) async -> [PlayableContent] {
            { offset, descending in
                guard offset == 0 else { return [] }
                return await plexShelf(by: order, descending: descending)
            }
        }
        return [
            PlayableListSort(name: "Recent Activity", action: sort(.recentActivity)),
            PlayableListSort(name: "Title", ascendingLabel: "A–Z", descendingLabel: "Z–A", action: sort(.title)),
            PlayableListSort(name: "Author", ascendingLabel: "A–Z", descendingLabel: "Z–A", action: sort(.author)),
            PlayableListSort(name: "Release Date", ascendingLabel: "Old to New", descendingLabel: "New to Old", defaultsToDescending: true, action: sort(.released)),
            PlayableListSort(name: "Date Added", ascendingLabel: "Old to New", descendingLabel: "New to Old", defaultsToDescending: true, action: sort(.added))
        ]
    }

    /// The orders a server's every-book list offers, Audible's: Plex's
    /// books are read whole, so it's sorted here, except by length, which
    /// a book's listing doesn't give.
    enum PlexOrder {
        /// Listened to last first, then the rest by when they were added.
        case recentActivity
        case title, author, released, added
    }

    /// The Plex shelf in `order`, reversed when `descending`.
    static func plexShelf(by order: PlexOrder, descending: Bool) async -> [PlayableContent] {
        let store = AudiobookProgressStore.shared
        // The last read when it's from the past few minutes: the list reads
        // again for each order picked.
        let books = (await plexItems(maxAge: 300) ?? []).compactMap { item in
            item.toPlayable.map { (item: item, book: $0, progress: store.progress(for: $0)) }
        }
        func byTitle(_ a: PlexAudiobookItem, _ b: PlexAudiobookItem) -> Bool {
            (a.titleSort ?? a.title).localizedStandardCompare(b.titleSort ?? b.title) == .orderedAscending
        }
        let sorted: [(item: PlexAudiobookItem, book: PlayableContent, progress: AudiobookProgress?)]
        switch order {
        case .recentActivity:
            // This device's reading, else Plex's last play of a file.
            func listened(_ entry: (item: PlexAudiobookItem, book: PlayableContent, progress: AudiobookProgress?)) -> Date? {
                entry.progress?.updatedAt ?? entry.item.lastViewedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            }
            sorted = books.sorted {
                switch (listened($0), listened($1)) {
                case let (a?, b?): a > b
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): ($0.item.addedAt ?? 0) > ($1.item.addedAt ?? 0)
                }
            }
            return sorted.map { $0.book.withAudiobookProgress($0.progress) }
        case .title:
            sorted = books.sorted { byTitle($0.item, $1.item) }
        case .author:
            sorted = books.sorted {
                let order = ($0.item.parentTitle ?? "").localizedStandardCompare($1.item.parentTitle ?? "")
                return order == .orderedSame ? byTitle($0.item, $1.item) : order == .orderedAscending
            }
        case .released:
            sorted = books.sorted {
                ($0.item.year ?? 0, $0.item.addedAt ?? 0) < ($1.item.year ?? 0, $1.item.addedAt ?? 0)
            }
        case .added:
            sorted = books.sorted { ($0.item.addedAt ?? 0) < ($1.item.addedAt ?? 0) }
        }
        return (descending ? sorted.reversed() : sorted).map { $0.book.withAudiobookProgress($0.progress) }
    }

    /// Every Plex book, and the ones added last, newest first, for a row of
    /// covers: one read for both, from the server. Nil when it couldn't be
    /// read.
    static func plexBooksAndNewest(limit: Int = 12) async -> (all: [PlayableContent], newest: [PlayableContent])? {
        guard let books = await plexItems(maxAge: 0) else { return nil }
        return shelves(of: books, limit: limit)
    }

    /// The same from the last read kept, at once: nil when there's none for
    /// the server picked.
    static func cachedPlexBooksAndNewest(limit: Int = 12) -> (all: [PlayableContent], newest: [PlayableContent])? {
        guard let snapshot = plexSnapshot, snapshot.server == MusicSearchService.shared.plexServerID else { return nil }
        return shelves(of: snapshot.items, limit: limit)
    }

    private static func shelves(of books: [PlexAudiobookItem], limit: Int) -> (all: [PlayableContent], newest: [PlayableContent]) {
        let newest = books
            .sorted { ($0.addedAt ?? 0) > ($1.addedAt ?? 0) }
            .prefix(limit)
            .compactMap(\.toPlayable)
        return (books.compactMap(\.toPlayable), newest)
    }

    // MARK: - Plex's books, kept

    /// Plex's books as last read, by server, in Caches (`ShelfCache`): the
    /// Audiobooks tab and the list of every book draw from it at once.
    private struct PlexSnapshot: Codable, Sendable {
        /// A book as read, with what the read sets on it after decoding
        /// (its id and cover URL), which isn't encoded with it: without
        /// them a kept book made no row, and the shelf came up empty. The
        /// cover URL carries the server's token, as the saved queue's rows
        /// already do (`LocalQueue.json`); the cover itself is cached by
        /// the book, so a URL for another of the server's addresses still
        /// draws it.
        struct Book: Codable, Sendable {
            let item: PlexAudiobookItem
            let sonosID: String?
            let thumbImageURL: URL?

            init(_ item: PlexAudiobookItem) {
                self.item = item
                sonosID = item.sonosID
                thumbImageURL = item.thumbImageURL
            }

            var restored: PlexAudiobookItem {
                var item = item
                item.sonosID = sonosID
                item.thumbImageURL = thumbImageURL
                return item
            }
        }

        let server: String
        let books: [Book]
        var readAt: Date

        var items: [PlexAudiobookItem] { books.map(\.restored) }
    }

    private static var plexSnapshot: PlexSnapshot? = ShelfCache.load(PlexSnapshot.self, named: "PlexBooks")

    /// Every Plex book: the last read when it's younger than `maxAge`, else
    /// the server's, which is kept. When the server can't be read, the last
    /// read of it, however old, rather than nothing; nil with none.
    static func plexItems(maxAge: TimeInterval) async -> [PlexAudiobookItem]? {
        let server = MusicSearchService.shared.plexServerID
        let kept = plexSnapshot.flatMap { $0.server == server ? $0 : nil }
        if let kept, Date.now.timeIntervalSince(kept.readAt) < maxAge { return kept.items }
        guard let items = await PlexAPI.shared.audiobooks() else {
            if kept != nil { log.info("plex shelf: server not read, showing the last read") }
            return maxAge == 0 ? nil : kept?.items
        }
        if let server {
            let snapshot = PlexSnapshot(server: server, books: items.map(PlexSnapshot.Book.init), readAt: .now)
            plexSnapshot = snapshot
            ShelfCache.save(snapshot, named: "PlexBooks")
        }
        return items
    }

    /// The next read goes to the server: after a scan, which may have found
    /// books.
    static func plexBooksChanged() {
        plexSnapshot?.readAt = .distantPast
    }

    /// Plex's books in series, from what Audible says of each
    /// (`AudiobookDetails`), each in its order.
    @MainActor
    static func plexSeries(_ books: [PlayableContent]) -> [AudiobookSeries] {
        let details = AudiobookDetails.shared
        let grouped = Dictionary(grouping: books.compactMap { book in
            details.details(for: book)?.series.map { (series: $0, book: book) }
        }, by: \.series)
        return grouped.map { name, entries in
            AudiobookSeries(id: "plex|\(name)", name: name, books: entries.map(\.book).sorted(by: details.inSeriesOrder))
        }
    }

    /// Has Plex scan its book libraries and waits for it, for a pull to
    /// refresh: a book added on the server shows without opening Plex.
    static func scanPlexBooks() async {
        await PlexBookScan.shared.run()
        plexBooksChanged()
    }

    /// Asks the Plex server whether it has books, for the Audiobooks tab,
    /// which shows from the answer kept at launch. Only a server with books
    /// changes it, unless `afterChange` (the listener just changed which
    /// libraries are books): one that couldn't be reached reads as none,
    /// and a blip shouldn't take the tab away.
    static func checkPlexBooks(afterChange: Bool = false) async {
        let has = await PlexAPI.shared.hasAudiobooks()
        // Written only when it changes: every view holding the key redraws
        // on a write, and this runs each time the tab shows.
        guard has || afterChange, UserDefaults.standard.bool(forKey: AppStorageKeys.hasPlexAudiobooks) != has else { return }
        UserDefaults.standard.set(has, forKey: AppStorageKeys.hasPlexAudiobooks)
    }

    /// Every book listened to, once each, newest first: this device's
    /// history and Audiobookshelf's books in progress, from the servers
    /// shown (`plex`, `audiobookshelf`). Ordered by when each book's place
    /// last moved; history's order breaks ties, so a book with no reading
    /// yet stays where the history has it.
    static func listenedBooks(plex: Bool, audiobookshelf: Bool) -> [PlayableContent] {
        let store = AudiobookProgressStore.shared
        let history = Array(PlayHistoryService.shared.history).filter { $0.content.type == .audiobook }
        let candidates = history + (audiobookshelf ? AudiobookshelfBrowseService.shared.continueListening : [])
        var books: [PlayableContent] = []
        for book in candidates where !books.contains(where: { $0.isSameBook(as: book) }) {
            let isShown = switch book.content.service {
            case .plex: plex
            case .audiobookshelf: audiobookshelf
            default: false
            }
            if isShown { books.append(book) }
        }
        return books.enumerated().sorted { lhs, rhs in
            let left = store.progress(for: lhs.element)?.updatedAt ?? .distantPast
            let right = store.progress(for: rhs.element)?.updatedAt ?? .distantPast
            return left == right ? lhs.offset < rhs.offset : left > right
        }.map(\.element)
    }

    // MARK: - A book

    /// The book read whole: from its own server, else — offline, or with
    /// the server out of reach — the copy kept with its download
    /// (`AudiobookDownloads`). Nil when neither has it, or it has no files.
    static func load(_ book: PlayableContent) async -> Audiobook? {
        // Offline, asking the server would only wait out its timeout.
        if OfflineMode.shared.isActive, let copy = AudiobookDownloads.copy(of: book) {
            return copy
        }
        guard var loaded = await loadFromServer(book) else {
            if let copy = AudiobookDownloads.copy(of: book) {
                log.notice("\(book.title, privacy: .public): server out of reach, opened the downloaded copy")
                return copy
            }
            return nil
        }
        // A read whose chapter marks didn't come — a request that failed on
        // a poor connection — keeps those of the last read of the same files.
        if loaded.chapters.count <= 1, let last = AudiobookReadCache.read(of: book), last.chapters.count > 1, last.timeline == loaded.timeline {
            log.notice("\(book.title, privacy: .public): no chapters this read, kept the last read's \(last.chapters.count)")
            loaded.chapters = last.chapters
        }
        AudiobookReadCache.keep(loaded)
        AudiobookDownloads.refresh(loaded)
        // Its files on this device play whatever the server can open.
        if loaded.filesMissing == true, AudiobookDownloads.hasAllFiles(loaded) {
            loaded.filesMissing = nil
        }
        sendNewerPlace(of: loaded)
        return loaded
    }

    /// The book as last read, for its page to show while it's read again:
    /// the read kept in Caches, else the copy kept with its download. Nil
    /// for a book never read on this device.
    static func lastRead(of book: PlayableContent) -> Audiobook? {
        if let read = AudiobookReadCache.read(of: book) { return read }
        // Kept in memory once read: a page asks each time it's made, and
        // the copy is a file to decode.
        guard let copy = AudiobookDownloads.copy(of: book) else { return nil }
        AudiobookReadCache.remember(copy)
        return copy
    }

    /// Tells the book's server where this device has the listener when
    /// that's newer than what the server holds: a place moved, or a book
    /// finished, with no server to tell (offline), so its other players
    /// pick up here. A minute's grace covers the reading this device's own
    /// syncs already gave it.
    static func sendNewerPlace(of audiobook: Audiobook) {
        guard let local = AudiobookProgressStore.shared.progress(for: audiobook.book) else { return }
        if let server = audiobook.serverProgress, server.updatedAt.addingTimeInterval(AudiobookProgress.serverGrace) >= local.updatedAt { return }
        switch audiobook.book.content.service {
        case .audiobookshelf:
            sendNewerAudiobookshelfPlace(local, of: audiobook)
        case .plex:
            sendNewerPlexPlace(local, of: audiobook)
        default:
            break
        }
    }

    /// Plex hears this device's plays from its timeline reports as they
    /// happen, but not those with no server to hear them (offline, a
    /// downloaded book). A finish is marked; a place in a later file than
    /// Plex's marks the files before it played (all Plex keeps, without
    /// Store track progress) and reports the place in its file, paused, as
    /// a Plex app's would be.
    private static func sendNewerPlexPlace(_ local: AudiobookProgress, of audiobook: Audiobook) {
        let server = audiobook.serverProgress
        if local.isFinished {
            guard server?.isFinished != true, let key = audiobook.book.plexRatingKey else { return }
            log.notice("\(audiobook.book.title, privacy: .public): telling Plex it's finished")
            Task { await PlexAPI.shared.markPlayed(ratingKey: key, true) }
            return
        }
        let timeline = audiobook.timeline
        let here = timeline.location(at: local.position)
        let there = server.map { timeline.location(at: $0.position) } ?? (part: 0, offset: 0)
        guard here.part > there.part || (here.part == there.part && there.offset > 0 && local.position > (server?.position ?? 0) + 60),
              audiobook.parts.indices.contains(here.part), let key = audiobook.parts[here.part].plexRatingKey else { return }
        let played = (there.part..<here.part).filter(audiobook.parts.indices.contains).compactMap { audiobook.parts[$0].plexRatingKey }
        let length = timeline.partDurations[here.part]
        log.notice("\(audiobook.book.title, privacy: .public): telling Plex this device's newer place, \(Int(local.position)) s (file \(here.part + 1))")
        Task {
            for file in played {
                await PlexAPI.shared.markPlayed(ratingKey: file, true)
            }
            await PlexAPI.shared.reportTimeline(ratingKey: key, state: .paused, time: here.offset, duration: length)
        }
    }

    private static func sendNewerAudiobookshelfPlace(_ local: AudiobookProgress, of audiobook: Audiobook) {
        let itemID = audiobook.book.content.id
        let duration = audiobook.duration
        // Unmarking a book the server has finished takes it back to the
        // start, and drops the place sent with it: the place goes again,
        // once the book is unfinished there.
        let unfinishes = audiobook.serverProgress?.isFinished == true && !local.isFinished
        log.notice("\(audiobook.book.title, privacy: .public): sending this device's newer place, \(Int(local.position)) s\(local.isFinished ? ", finished" : "", privacy: .public)")
        Task {
            let api = AudiobookshelfAPI.shared
            if unfinishes {
                await api.updateProgress(itemID: itemID, currentTime: local.position, duration: duration, isFinished: false)
            }
            await api.updateProgress(itemID: itemID, currentTime: local.position, duration: duration, isFinished: local.isFinished)
        }
    }

    /// The Plex server a book's id names (`<server>:3:<rating key>`).
    private static func plexServerID(of book: PlayableContent) -> String? {
        let parts = (book.content.id.removingPercentEncoding ?? book.content.id).components(separatedBy: ":")
        return parts.count >= 3 ? parts[0] : nil
    }

    /// The book read whole from its own server alone.
    static func loadFromServer(_ book: PlayableContent) async -> Audiobook? {
        switch book.content.service {
        case .plex:
            return await loadPlex(book)
        case .audiobookshelf:
            return await loadAudiobookshelf(book)
        default:
            return nil
        }
    }

    private static func loadPlex(_ book: PlayableContent) async -> Audiobook? {
        guard let key = book.plexRatingKey else { return nil }
        // A book of another server than the one chosen now (from history,
        // Continue Listening, Downloads): its rating key there is some other
        // item here. Its download's copy, if any, opens instead.
        if let server = plexServerID(of: book), let chosen = PlexAPI.shared.serverID, server != chosen {
            log.notice("\(book.title, privacy: .public) is on another Plex server than the one chosen")
            return nil
        }
        async let details = PlexAPI.shared.audiobook(ratingKey: key)
        guard let files = await PlexAPI.shared.audiobookParts(ratingKey: key), !files.isEmpty else {
            log.error("plex book \(key, privacy: .public): no files")
            return nil
        }
        let timeline = PlexAudiobook.timeline(parts: files)
        // Side by side: whether Plex can open the files, and the marks it
        // lists for them. Only reading the files themselves waits on the
        // first.
        // Marks kept from an earlier read, Plex's or the file's own, are
        // the file's as it is now: Plex is asked only for the rest.
        var kept: [String: [AudiobookChapterMark]] = [:]
        for part in files {
            kept[part.ratingKey] = await AudiobookChapterReader.keptMarks(chapterCacheKey(part))
        }
        let unknown = files.filter { kept[$0.ratingKey] == nil }
        async let missingCheck = isMissing(files.first?.streamURL)
        async let listed = PlexAPI.shared.audiobookChapterMarks(parts: unknown)
        let missing = await missingCheck
        if missing {
            let folder = files.first?.media?.first?.part.first.map { ($0.file as NSString).deletingLastPathComponent } ?? "?"
            log.error("plex book \(key, privacy: .public): Plex can't open its files (404), kept in \(folder, privacy: .public)")
        }
        let listedNow = await listed
        var byFile: [String: [AudiobookChapterMark]] = [:]
        for part in unknown {
            byFile[chapterCacheKey(part)] = listedNow[part.ratingKey]
        }
        await AudiobookChapterReader.keepListed(byFile)
        if !kept.isEmpty {
            log.info("plex book \(key, privacy: .public): marks kept for \(kept.count) of \(files.count) files")
        }
        let marks = await plexChapterMarks(files, listed: kept.merging(listedNow) { old, _ in old }, readingFiles: !missing)
        let item = await details
        var chapters = PlexAudiobook.chapters(parts: files, marks: marks, timeline: timeline)
        if chapters.count <= 1 {
            log.notice("plex book \(key, privacy: .public): no chapter marks; guid \(item?.guid ?? "none", privacy: .public)")
        }
        // No marks anywhere: Audible's, for a book the Audnexus agent matched.
        if chapters.count <= 1, let match = AudnexusChapters.asin(fromPlexGuid: item?.guid) {
            let region = match.region ?? "us"
            if let audible = await AudiobookChapterReader.audibleChapters(asin: match.asin, duration: timeline.duration, lookup: {
                await AudnexusAPI.chapters(asin: match.asin, region: region)
            }) {
                log.info("plex book \(key, privacy: .public): \(audible.count) chapters from Audible")
                chapters = audible
            }
        }
        // Nor matched there: Audible's edition as long as the book, found by
        // its title and author.
        if chapters.count <= 1, !missing,
           let audible = await AudiobookChapterReader.searchedAudibleChapters(title: item?.title ?? book.title, author: item?.parentTitle, duration: timeline.duration) {
            chapters = audible
        }
        return Audiobook(
            // The server's own copy where it answered: a shelf's row may
            // carry what's left in its subtitle, which history shouldn't keep.
            book: item?.toPlayable ?? book,
            parts: files.map(\.toPlayable),
            timeline: timeline,
            chapters: chapters,
            narrator: nil,
            summary: readable(item?.summary),
            serverProgress: PlexAudiobook.progress(parts: files, timeline: timeline),
            filesMissing: missing
        )
    }

    /// Whether the server answers "not found" for a file it lists, asked
    /// for its first byte; only the answer's head is read, so a server that
    /// ignores the range doesn't send the whole file. Plex answers so when
    /// the file has moved since its scan, or its library's folder is out of
    /// its reach; anything else (no answer, a slow one) isn't missing.
    private nonisolated static func isMissing(_ url: URL?) async -> Bool {
        guard let url else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.addValue("bytes=0-0", forHTTPHeaderField: "Range")
        guard let (body, response) = try? await URLSession.shared.bytes(for: request) else { return false }
        body.task.cancel()
        let status = (response as? HTTPURLResponse)?.statusCode
        return status == 404 || status == 410
    }

    /// The chapter marks in a Plex book's files: those Plex lists
    /// (`listed`), else the file's own for a file Plex has none for (it
    /// lists an `.m4b`'s only when it read them at scan), unless the files
    /// can't be read. An mp3's own marks never come this way: Plex sends an
    /// mp3 without its ID3 tag, `download=1` too, so its `CHAP` frames are
    /// gone (the same file from Audiobookshelf, sent whole, keeps them).
    private static func plexChapterMarks(_ files: [PlexMetadata], listed: [String: [AudiobookChapterMark]], readingFiles: Bool) async -> [String: [AudiobookChapterMark]] {
        var marks = listed
        let fromPlex = marks.count
        let unmarked = files.filter { marks[$0.ratingKey] == nil && ($0.chapters ?? []).isEmpty }
        if readingFiles, !unmarked.isEmpty, files.count <= AudiobookChapterReader.fileLimit {
            let read = await AudiobookChapterReader.marks(in: unmarked.map { (key: chapterCacheKey($0), url: $0.streamURL) })
            for part in unmarked {
                marks[part.ratingKey] = read[chapterCacheKey(part)]
            }
        }
        let types = files.map { $0.streamURL?.pathExtension ?? "?" }
        log.info("plex book: \(files.count) files (\(types, privacy: .public)), marks for \(fromPlex) from Plex, \(marks.count - fromPlex) from the files")
        return marks
    }

    /// A Plex file as the chapter cache knows it: a file replaced on the
    /// server is read again.
    private static func chapterCacheKey(_ part: PlexMetadata) -> String {
        "plex:\(part.ratingKey):\(part.updatedAt ?? 0):\(part.duration ?? 0)"
    }

    private static func loadAudiobookshelf(_ book: PlayableContent) async -> Audiobook? {
        guard let item = await AudiobookshelfAPI.shared.item(id: book.content.id), item.hasAudio else {
            log.error("audiobookshelf book \(book.content.id, privacy: .public): couldn't be read")
            return nil
        }
        let parts = item.partsToPlayable()
        // The timeline is laid out from every file; a file Cue couldn't
        // address would put every place after it in the wrong one.
        guard !parts.isEmpty, parts.count == item.timeline.partDurations.count else {
            log.error("audiobookshelf book \(book.content.id, privacy: .public): \(parts.count) of \(item.timeline.partDurations.count) files playable")
            return nil
        }
        let metadata = item.media?.metadata
        return Audiobook(
            book: item.toPlayable,
            parts: parts,
            timeline: item.timeline,
            chapters: await audiobookshelfChapters(item, parts: parts),
            narrator: metadata?.narratorName.flatMap { $0.isEmpty ? nil : $0 },
            summary: readable(metadata?.description),
            serverProgress: item.progress,
            filesMissing: item.isMissing
        )
    }

    /// An Audiobookshelf book's chapters: the server's, else the marks in
    /// its files for a book the server found none in, else Audible's for a
    /// book matched there (looked up by the server, as its chapter editor
    /// does), else for the edition found by its title and author.
    private static func audiobookshelfChapters(_ item: AudiobookshelfItem, parts: [PlayableContent]) async -> [AudiobookChapter] {
        guard (item.media?.chapters ?? []).isEmpty else { return item.chapters }
        // An episode's are its feed's or its file's: Audible has none, and
        // an episode's title would find some book's.
        if item.isEpisode {
            let key = "audiobookshelf:\(parts.first?.content.id ?? item.id)"
            let marks = await AudiobookChapterReader.marks(in: parts.prefix(1).map { part in
                (key: key, url: AudiobookshelfAPI.fileURL(for: part.content.id, fileExtension: part.metadata?.audioCodec))
            })
            guard let found = marks[key], !found.isEmpty else { return item.chapters }
            return .from(files: [(title: item.media?.metadata?.title ?? "Episode", marks: found)], timeline: item.timeline)
        }
        let keys = parts.map { "audiobookshelf:\($0.content.id)" }
        // The file itself, not a session's track: a session held here may
        // have ended on the server.
        let marks = await AudiobookChapterReader.marks(in: zip(keys, parts).map { key, part in
            (key: key, url: AudiobookshelfAPI.fileURL(for: part.content.id, fileExtension: part.metadata?.audioCodec))
        })
        log.info("audiobookshelf book: \(parts.count) files, marks for \(marks.count) from the files")
        if !marks.isEmpty {
            let tracks = item.media?.tracks ?? []
            let files = keys.enumerated().map { index, key in
                (title: tracks.indices.contains(index) ? tracks[index].title ?? "Part \(index + 1)" : "Part \(index + 1)", marks: marks[key] ?? [])
            }
            return .from(files: files, timeline: item.timeline)
        }
        if item.chapters.count <= 1, let asin = item.media?.metadata?.asin?.uppercased(), AudnexusChapters.isASIN(asin) {
            let duration = item.timeline.duration
            if let audible = await AudiobookChapterReader.audibleChapters(asin: asin, duration: duration, lookup: {
                await AudiobookshelfAPI.shared.audibleChapters(asin: asin)
            }) {
                log.info("audiobookshelf book: \(audible.count) chapters from Audible")
                return audible
            }
            log.info("audiobookshelf book \(asin, privacy: .public): no Audible chapters that fit \(Int(duration)) s")
        }
        // Nor matched there: Audible's edition as long as the book, found by
        // its title and author.
        if item.chapters.count <= 1, item.isMissing != true, let title = item.media?.metadata?.title,
           let audible = await AudiobookChapterReader.searchedAudibleChapters(title: title, author: item.media?.metadata?.authorName, duration: item.timeline.duration) {
            return audible
        }
        return item.chapters
    }

    /// A book's description as text: servers keep it as HTML.
    private static func readable(_ description: String?) -> String? {
        guard let description else { return nil }
        let text = AudiobookText.plain(description)
        return text.isEmpty ? nil : text
    }

    /// Opens a listening session for an Audiobookshelf book and points its
    /// files at the session's track URLs, which a speaker can fetch with no
    /// sign-in. Nil when the server wouldn't open one.
    static func openAudiobookshelfSession(for audiobook: Audiobook) async -> Audiobook? {
        guard await AudiobookshelfAPI.shared.startSession(itemID: audiobook.book.content.id) != nil else {
            log.error("audiobookshelf book \(audiobook.book.content.id, privacy: .public): no session")
            return nil
        }
        var opened = audiobook
        opened.parts = audiobook.parts.map { part in
            var part = part
            part.previewURL = AudiobookshelfAPI.streamURL(for: part.content.id, fileExtension: part.metadata?.audioCodec, destination: .device)
            return part
        }
        return opened
    }

    // MARK: - Where it was left

    /// Where to pick the book up: this device's reading or the server's
    /// (`preferring`).
    static func progress(for audiobook: Audiobook) -> AudiobookProgress? {
        preferring(local: AudiobookProgressStore.shared.progress(for: audiobook.book), server: audiobook.serverProgress, in: audiobook)
    }

    /// This device's reading of `audiobook`, unless the server's is clearly
    /// newer. A Plex reading that knows only which file was played moves
    /// this device on only past the file it's in (`PlexAudiobook.preferring`).
    static func preferring(local: AudiobookProgress?, server: AudiobookProgress?, in audiobook: Audiobook) -> AudiobookProgress? {
        guard audiobook.book.content.service == .plex else {
            return AudiobookProgress.preferring(local: local, server: server)
        }
        if let local, let server, isFinishedElsewhere(local: local, server: server, in: audiobook) {
            return server
        }
        return PlexAudiobook.preferring(local: local, server: server, timeline: audiobook.timeline)
    }

    /// Whether Plex calling the book finished is another player finishing
    /// it: clearly newer than this device's place, and nothing this device
    /// did. Plex counts a file played once reports carry it past 90%, so
    /// with this device's place that far into the last file, the finish
    /// may be its own; and it counted a file played on the report sent as
    /// this device left the book (before a book file left partway was
    /// reported paused), so a finish dated then is this device's too.
    private static func isFinishedElsewhere(local: AudiobookProgress, server: AudiobookProgress, in audiobook: Audiobook) -> Bool {
        guard server.isFinished, !local.isFinished,
              server.updatedAt > local.updatedAt.addingTimeInterval(AudiobookProgress.serverGrace) else { return false }
        let timeline = audiobook.timeline
        guard let last = timeline.partDurations.indices.last else { return false }
        let ownScrobble = timeline.start(ofPart: last) + timeline.partDurations[last] * PlayReporter.playedThreshold
        guard local.position < ownScrobble else { return false }
        let left = AudiobookPlaceHistory.shared.places(for: audiobook.book).first { $0.kind == .left }
        if let left, abs(left.date.timeIntervalSince(server.updatedAt)) < 120 { return false }
        return true
    }

    /// Marks the book finished, or not started, here and on its server.
    static func markFinished(_ audiobook: Audiobook, _ finished: Bool) async {
        let store = AudiobookProgressStore.shared
        // The book playing: stopped, and what was heard kept first, or its
        // next reading would undo the mark.
        await AudiobookPlayer.shared.noteMarked(audiobook.book)
        // Where it was stays in the book's history, so a mark made by
        // mistake loses no place.
        if let reading = store.progress(for: audiobook.book), !reading.isFinished, reading.position > 0 {
            AudiobookPlaceHistory.shared.record(.marked, at: reading.position, to: finished ? audiobook.duration : 0, for: audiobook.book)
        }
        if finished {
            store.record(AudiobookProgress(position: audiobook.duration, duration: audiobook.duration, isFinished: true), for: audiobook.book)
        } else {
            store.record(AudiobookProgress(position: 0, duration: audiobook.duration), for: audiobook.book)
        }
        switch audiobook.book.content.service {
        case .plex:
            guard let key = audiobook.book.plexRatingKey else { return }
            await PlexAPI.shared.markPlayed(ratingKey: key, finished)
        case .audiobookshelf:
            await AudiobookshelfAPI.shared.updateProgress(
                itemID: audiobook.book.content.id,
                currentTime: finished ? audiobook.duration : 0,
                duration: audiobook.duration,
                isFinished: finished
            )
        default:
            break
        }
    }
}
