import Foundation
import Observation
import SonosKit

/// The words looked up in each book's transcript, so a word whose meaning
/// was wanted once can be found again: a tap on a word in Read Along keeps
/// it here, with the words around it and where in the book it was. The
/// book's history (`AudiobookHistoryList`) shows them among its places, and
/// the Audiobooks tab's Words (`BookWordsScreen`) every book's, each opening
/// the dictionary again.
///
/// Kept apart from `AudiobookPlaceHistory`, whose 50 places a book would
/// soon give over to words. In a file in Application Support, the newest
/// `limit` of each book.
@MainActor
@Observable
final class BookWordLookups {
    static let shared = BookWordLookups()

    /// A word looked up, and where.
    struct Lookup: Codable, Hashable, Identifiable {
        var id = UUID()
        /// The word as it was tapped, without the punctuation around it.
        let term: String
        let date: Date
        /// Book time of the start of its line, to play from.
        let position: TimeInterval
        /// The words before and after it in its line, a few either side,
        /// with "…" where the line goes on.
        let before: String
        let after: String
    }

    /// Each book's words, newest first, by `AudiobookProgressStore.key`.
    private(set) var lookups: [String: [Lookup]] = [:]
    /// The book each list is of, for Words to show it and play from it.
    private(set) var books: [String: PlayableContent] = [:]

    /// A book with words looked up in it, and those words, newest first.
    struct Shelf: Identifiable {
        var id: String { key }
        let key: String
        let book: PlayableContent
        let lookups: [Lookup]
    }

    /// A word looked up, and the book it was in.
    struct Word: Identifiable {
        var id: UUID { lookup.id }
        let lookup: Lookup
        let book: PlayableContent
    }

    /// What's kept in the file.
    private struct Stored: Codable {
        var lookups: [String: [Lookup]]
        var books: [String: PlayableContent]
    }

    /// How many words each book keeps.
    private static let limit = 100
    /// The same word in the same line again this soon is the same lookup:
    /// another word tapped in between, and back.
    private static let sameMoment: TimeInterval = 10 * 60

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    private static let io = DispatchQueue(label: "dance.cue.bookWordLookups", qos: .utility)

    private init() {
        guard let url = Self.fileURL, let data = try? Data(contentsOf: url) else { return }
        if let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            lookups = stored.lookups
            books = stored.books
        } else if let words = try? JSONDecoder().decode([String: [Lookup]].self, from: data) {
            // Kept before the books were: each book's comes back as its
            // history is opened (`keep(_:)`).
            lookups = words
        }
    }

    func lookups(for book: PlayableContent) -> [Lookup] {
        lookups[AudiobookProgressStore.key(for: book)] ?? []
    }

    /// Every book with words looked up in it, the one looked up in last
    /// first; with `search`, only the words with it in them or around them.
    func shelves(matching search: String = "") -> [Shelf] {
        let search = search.trimmingCharacters(in: .whitespaces)
        return lookups.compactMap { key, list -> Shelf? in
            guard let book = books[key] else { return nil }
            let found = search.isEmpty ? list : list.filter {
                $0.term.localizedCaseInsensitiveContains(search)
                    || "\($0.before) \($0.after)".localizedCaseInsensitiveContains(search)
            }
            return found.isEmpty ? nil : Shelf(key: key, book: book, lookups: found)
        }
        .sorted { ($0.lookups.first?.date ?? .distantPast) > ($1.lookups.first?.date ?? .distantPast) }
    }

    /// The words looked up last, in any book, newest first.
    func recent(_ count: Int) -> [Word] {
        var all: [Word] = []
        for (key, list) in lookups {
            guard let book = books[key] else { continue }
            all += list.map { Word(lookup: $0, book: book) }
        }
        return Array(all.sorted { $0.lookup.date > $1.lookup.date }.prefix(count))
    }

    /// Notes which book `book`'s words are of, for words kept before that
    /// was: they show in Words once it's known.
    func keep(_ book: PlayableContent) {
        let key = AudiobookProgressStore.key(for: book)
        guard books[key] == nil, lookups[key] != nil else { return }
        books[key] = book
        scheduleSave()
    }

    /// Keeps `term`, looked up in the line starting at book time
    /// `position`, unless it was just looked up there.
    func record(_ term: String, before: String, after: String, at position: TimeInterval, in book: PlayableContent) {
        let key = AudiobookProgressStore.key(for: book)
        var list = lookups[key] ?? []
        let isRepeat = list.contains {
            $0.term.localizedCaseInsensitiveCompare(term) == .orderedSame
                && abs($0.position - position) < 1
                && Date.now.timeIntervalSince($0.date) < Self.sameMoment
        }
        guard !isRepeat else { return }
        list.insert(Lookup(term: term, date: .now, position: max(position, 0), before: before, after: after), at: 0)
        lookups[key] = Array(list.prefix(Self.limit))
        books[key] = book
        scheduleSave()
    }

    /// Takes `lookup` off `book`'s list.
    func remove(_ lookup: Lookup, from book: PlayableContent) {
        let key = AudiobookProgressStore.key(for: book)
        guard var list = lookups[key] else { return }
        list.removeAll { $0.id == lookup.id }
        lookups[key] = list.isEmpty ? nil : list
        if list.isEmpty { books[key] = nil }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Writes now, for the app leaving the foreground, if anything changed
    /// since the last write.
    func save() {
        guard let saveTask else { return }
        saveTask.cancel()
        self.saveTask = nil
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(Stored(lookups: lookups, books: books)) else { return }
        Self.io.async {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static var fileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("BookWordLookups.json")
    }
}
