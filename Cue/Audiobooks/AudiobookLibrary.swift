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
        let marks = await plexChapterMarks(files)
        let item = await details
        let summary = item?.summary
        return Audiobook(
            // The server's own copy where it answered: a shelf's row may
            // carry what's left in its subtitle, which history shouldn't keep.
            book: item?.toPlayable ?? book,
            parts: files.map(\.toPlayable),
            timeline: timeline,
            chapters: PlexAudiobook.chapters(parts: files, marks: marks, timeline: timeline),
            narrator: nil,
            summary: summary.flatMap { $0.isEmpty ? nil : $0 },
            serverProgress: PlexAudiobook.progress(parts: files, timeline: timeline)
        )
    }

    /// The chapter marks in a Plex book's files: Plex's, else the file's
    /// own for a file Plex has none for (it lists an `.m4b`'s only when it
    /// read them at scan).
    private static func plexChapterMarks(_ files: [PlexMetadata]) async -> [String: [AudiobookChapterMark]] {
        var marks = await PlexAPI.shared.audiobookChapterMarks(parts: files)
        let fromPlex = marks.count
        let unmarked = files.filter { marks[$0.ratingKey] == nil && ($0.chapters ?? []).isEmpty }
        if !unmarked.isEmpty, files.count <= AudiobookChapterReader.fileLimit {
            let read = await AudiobookChapterReader.marks(in: unmarked.map { (key: chapterCacheKey($0), url: $0.streamURL) })
            for part in unmarked {
                marks[part.ratingKey] = read[chapterCacheKey(part)]
            }
        }
        log.info("plex book: \(files.count) files, marks for \(fromPlex) from Plex, \(marks.count - fromPlex) from the files")
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
            summary: metadata?.description.flatMap { $0.isEmpty ? nil : $0 },
            serverProgress: item.progress
        )
    }

    /// An Audiobookshelf book's chapters: the server's, else the marks in
    /// its files for a book the server found none in.
    private static func audiobookshelfChapters(_ item: AudiobookshelfItem, parts: [PlayableContent]) async -> [AudiobookChapter] {
        guard (item.media?.chapters ?? []).isEmpty else { return item.chapters }
        let keys = parts.map { "audiobookshelf:\($0.content.id)" }
        let marks = await AudiobookChapterReader.marks(in: zip(keys, parts).map { (key: $0, url: $1.previewURL) })
        log.info("audiobookshelf book: \(parts.count) files, marks for \(marks.count) from the files")
        guard !marks.isEmpty else { return item.chapters }
        let tracks = item.media?.tracks ?? []
        let files = keys.enumerated().map { index, key in
            (title: tracks.indices.contains(index) ? tracks[index].title ?? "Part \(index + 1)" : "Part \(index + 1)", marks: marks[key] ?? [])
        }
        return .from(files: files, timeline: item.timeline)
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
