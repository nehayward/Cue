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
        let item = await details
        let summary = item?.summary
        return Audiobook(
            // The server's own copy where it answered: a shelf's row may
            // carry what's left in its subtitle, which history shouldn't keep.
            book: item?.toPlayable ?? book,
            parts: files.map(\.toPlayable),
            timeline: timeline,
            chapters: PlexAudiobook.chapters(parts: files, timeline: timeline),
            narrator: nil,
            summary: summary.flatMap { $0.isEmpty ? nil : $0 },
            serverProgress: PlexAudiobook.progress(parts: files, timeline: timeline)
        )
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
            chapters: item.chapters,
            narrator: metadata?.narratorName.flatMap { $0.isEmpty ? nil : $0 },
            summary: metadata?.description.flatMap { $0.isEmpty ? nil : $0 },
            serverProgress: item.progress
        )
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
