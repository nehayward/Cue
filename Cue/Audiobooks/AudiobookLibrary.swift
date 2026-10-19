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

    /// The Plex shelf's rows: every book, with what's left of each in its
    /// subtitle. Plex's own reading of where each book is comes only with
    /// the book's files, so this is this device's.
    static func plexShelf() async -> [PlayableContent] {
        let store = AudiobookProgressStore.shared
        return (await plexBooks() ?? []).map { $0.withAudiobookProgress(store.progress(for: $0)) }
    }

    /// Asks the Plex server whether it has books, for the Audiobooks tab,
    /// which shows from the answer kept at launch. Only a server with books
    /// changes it, unless `afterChange` (the listener just changed which
    /// libraries are books): one that couldn't be reached reads as none,
    /// and a blip shouldn't take the tab away.
    static func checkPlexBooks(afterChange: Bool = false) async {
        let has = await PlexAPI.shared.hasAudiobooks()
        guard has || afterChange else { return }
        UserDefaults.standard.set(has, forKey: AppStorageKeys.hasPlexAudiobooks)
    }

    // MARK: - A book

    /// The book read whole, from its own server. Nil when it couldn't be,
    /// or it has no files.
    static func load(_ book: PlayableContent) async -> Audiobook? {
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
        async let details = PlexAPI.shared.audiobook(ratingKey: key)
        guard let files = await PlexAPI.shared.audiobookParts(ratingKey: key), !files.isEmpty else {
            log.error("plex book \(key, privacy: .public): no files")
            return nil
        }
        let timeline = PlexAudiobook.timeline(parts: files)
        let missing = await isMissing(files.first?.streamURL)
        if missing {
            let folder = files.first?.media?.first?.part.first.map { ($0.file as NSString).deletingLastPathComponent } ?? "?"
            log.error("plex book \(key, privacy: .public): Plex can't open its files (404), kept in \(folder, privacy: .public)")
        }
        let marks = await plexChapterMarks(files, readingFiles: !missing)
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

    /// The chapter marks in a Plex book's files: Plex's, else the file's
    /// own for a file Plex has none for (it lists an `.m4b`'s only when it
    /// read them at scan), unless the files can't be read.
    private static func plexChapterMarks(_ files: [PlexMetadata], readingFiles: Bool) async -> [String: [AudiobookChapterMark]] {
        var marks = await PlexAPI.shared.audiobookChapterMarks(parts: files)
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

    /// Where to pick the book up: the newer of this device's reading and
    /// the server's.
    static func progress(for audiobook: Audiobook) -> AudiobookProgress? {
        AudiobookProgress.newer(AudiobookProgressStore.shared.progress(for: audiobook.book), audiobook.serverProgress)
    }

    /// Marks the book finished, or not started, here and on its server.
    static func markFinished(_ audiobook: Audiobook, _ finished: Bool) async {
        let store = AudiobookProgressStore.shared
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
