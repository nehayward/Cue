import Foundation
import MusicSearchKit
import OSLog
import SonosKit

/// Names for a book's chapters that say only their place ("Chapter 8",
/// "Track 001"), as Audible's often do, from the contents of a printed
/// edition on Open Library (`AudiobookChapterReader.lookUpNames`): Flies and
/// Spiders for The Hobbit's "Chapter 8", with its "Chapter 9", the rest of
/// that chapter, folded in.
///
/// Names kept from before are put on a book as it's read
/// (`AudiobookLibrary.load`). Looking them up waits on Open Library, seconds
/// at times, so it never holds a read up: it goes on behind, and the names
/// land on the book where it's held — the player, the read kept for its
/// page, its download's copy — and on the pages showing it (`applied(to:)`).
@MainActor
@Observable
final class AudiobookChapterNames {
    static let shared = AudiobookChapterNames()

    private static let log = Logger(subsystem: "dance.cue", category: "audiobooks")

    /// Names found this launch, by the book's key, beside the chapters they
    /// name.
    private var found: [String: Found] = [:]
    /// Books whose names are being looked up.
    @ObservationIgnored private var looking: Set<String> = []

    private struct Found {
        let numbered: [AudiobookChapter]
        let named: [AudiobookChapter]
    }

    private init() {}

    /// `audiobook` with the names found for its chapters this launch, for a
    /// page holding a read from before they came.
    func applied(to audiobook: Audiobook) -> Audiobook {
        guard let found = found[AudiobookProgressStore.key(for: audiobook.book)], found.numbered == audiobook.chapters else { return audiobook }
        var named = audiobook
        named.chapters = found.named
        return named
    }

    /// `audiobook` with its chapters named, when they say only their place
    /// and names were found before; else as it is, with names looked for
    /// behind it when they never were.
    func name(_ audiobook: Audiobook) async -> Audiobook {
        let chapters = audiobook.chapters
        guard AudiobookChapterNaming.namesAreNumbers(chapters) else { return audiobook }
        let key = AudiobookProgressStore.key(for: audiobook.book)
        if let found = found[key], found.numbered == chapters {
            return with(found.named, audiobook)
        }
        switch await AudiobookChapterReader.keptNames(for: chapters, title: audiobook.book.title, author: audiobook.book.bookAuthor, duration: audiobook.duration) {
        case let .named(named):
            found[key] = Found(numbered: chapters, named: named)
            return with(named, audiobook)
        case .noFit:
            return audiobook
        case .unknown:
            lookUp(audiobook)
            return audiobook
        }
    }

    /// Names for the book the player had when Cue was last closed, read
    /// from before or looked up: it isn't read again until it's played from
    /// a shelf or its page opens.
    func nameLoaded(_ audiobook: Audiobook) async {
        let named = await name(audiobook)
        guard named.chapters != audiobook.chapters else { return }
        AudiobookPlayer.shared.adoptChapters(named.chapters, replacing: audiobook.chapters, of: audiobook.book)
    }

    private func with(_ chapters: [AudiobookChapter], _ audiobook: Audiobook) -> Audiobook {
        var named = audiobook
        named.chapters = chapters
        return named
    }

    private func lookUp(_ audiobook: Audiobook) {
        // Offline, asking would only fail.
        guard !OfflineMode.shared.isActive else { return }
        let key = AudiobookProgressStore.key(for: audiobook.book)
        guard looking.insert(key).inserted else { return }
        let chapters = audiobook.chapters
        Task {
            defer { self.looking.remove(key) }
            guard let named = await AudiobookChapterReader.lookUpNames(for: chapters, title: audiobook.book.title, author: audiobook.book.bookAuthor) else { return }
            self.found[key] = Found(numbered: chapters, named: named)
            self.adopt(named, replacing: chapters, in: audiobook)
        }
    }

    /// Puts names that landed after `audiobook` was read wherever it's held
    /// with the chapters they name.
    private func adopt(_ named: [AudiobookChapter], replacing numbered: [AudiobookChapter], in audiobook: Audiobook) {
        if let read = AudiobookReadCache.read(of: audiobook.book), read.chapters == numbered {
            AudiobookReadCache.keep(with(named, read))
        }
        if let copy = AudiobookDownloads.copy(of: audiobook.book), copy.chapters == numbered {
            AudiobookDownloads.refresh(with(named, copy))
        }
        AudiobookPlayer.shared.adoptChapters(named, replacing: numbered, of: audiobook.book)
        Self.log.notice("\(audiobook.book.title, privacy: .public): \(named.count) chapters named")
    }
}
