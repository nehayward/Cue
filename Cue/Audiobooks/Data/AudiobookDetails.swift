import Foundation
import MusicSearchKit
import Nuke
import OSLog
import SonosKit
import UIKit

/// Who reads a book and the series it's in, for the book's page and the
/// Series shelf. Audiobookshelf says, on every book it lists (`note(_:)`).
/// Plex knows a book by its title and author only, so its books' are
/// Audible's (`AudibleCatalog`), as are an Audiobookshelf book's when the
/// server names no narrator: asked for as they're shown (`request(_:)`),
/// two at a time, and kept in Caches, so a book is asked about once. Only
/// an edition as long as the book names its narrator: Audible's first
/// answer was often another edition (Jim Dale's for Stephen Fry's), so with
/// none that fits the narrator stays unknown. A book Audible has nothing on
/// is asked again after a week.
@MainActor
@Observable
final class AudiobookDetails {
    static let shared = AudiobookDetails()

    struct Details: Codable, Equatable, Sendable {
        var narrators: [String] = []
        var series: String?
        /// The book's place in `series`, as the source writes it ("1",
        /// "2.5").
        var sequence: String?
        /// When Audible was asked, for a Plex book.
        var checked: Date?
        /// The Audible edition it was matched to by length, and its cover.
        var asin: String?
        var cover: URL?

        /// `sequence` as a number, to put a series in order.
        var place: Double? { sequence.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } }
    }

    /// By book (`AudiobookProgressStore.key(for:)`).
    private(set) var books: [String: Details] = [:]

    @ObservationIgnored private var pending: [PlayableContent] = []
    @ObservationIgnored private var asking: Set<String> = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    /// When a book's lookup last went unanswered (Audible refusing, no
    /// network), so it isn't asked again on every list and page that shows
    /// it: each would set off the whole lookup again, and a refusal for
    /// asking too often would never lift.
    @ObservationIgnored private var unansweredAt: [String: Date] = [:]
    /// Each cover's fingerprint, by book and cover URL: a cover doesn't
    /// change, so it's drawn and measured once.
    @ObservationIgnored private var fingerprints: [String: UInt64] = [:]

    private nonisolated static let log = Logger(subsystem: "dance.cue", category: "audiobooks")
    private static let recheckAfter: TimeInterval = 7 * 24 * 3600
    private static let retryAfter: TimeInterval = 30 * 60
    private static let concurrency = 2

    private static let cacheName = "AudiobookDetails"

    /// The file, with a version raised when what's kept changes: a file of
    /// another version is ignored and written over, so every book is asked
    /// about again.
    private struct Store: Codable, Sendable {
        static let currentVersion = 5
        var version: Int
        var books: [String: Details]
        var repeatedCovers: Set<String>?
    }

    /// Books whose server's cover is another book's in their series (by
    /// `AudiobookProgressStore.key(for:)`): those draw their Audible
    /// edition's cover instead (`coverContent(for:)`).
    private(set) var repeatedCovers: Set<String> = []

    /// Every book asked about, for comparing covers.
    @ObservationIgnored private var seen: [String: PlayableContent] = [:]

    private init() {
        if let kept = ShelfCache.load(Store.self, named: Self.cacheName) {
            guard kept.version == Store.currentVersion else { return }
            books = kept.books
            repeatedCovers = kept.repeatedCovers ?? []
        } else if let moved = Self.loadFromBefore(), moved.version == Store.currentVersion {
            books = moved.books
            repeatedCovers = moved.repeatedCovers ?? []
            // Where it's kept now, at once: the old file is gone.
            save()
        }
    }

    /// The store where it was kept before `ShelfCache`, at the top of
    /// Caches, read once and removed.
    private static func loadFromBefore() -> Store? {
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AudiobookDetails.json"),
            let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return try? JSONDecoder().decode(Store.self, from: data)
    }

    func details(for book: PlayableContent) -> Details? {
        books[AudiobookProgressStore.key(for: book)]
    }

    /// What a reading is called on a series' page: who reads it, or Full
    /// Cast for more than three. Nil when who reads it isn't known.
    static func narration(_ narrators: [String]) -> String? {
        guard !narrators.isEmpty else { return nil }
        return narrators.count > 3 ? "Full Cast" : narrators.formatted(.list(type: .and))
    }

    /// `book` to draw the cover of: the Audible edition's it was matched to
    /// when its server's cover is another book's in its series (Plex has
    /// the full-cast Harry Potters as Philosopher's Stone, which made the
    /// series a row of one picture), else its own. Not always Audible's:
    /// Audible changes an edition's cover over its life (Project Hail
    /// Mary's is the film's poster now), and the server's is usually the
    /// one the listener chose. Keyed by the edition (its id, with no album
    /// to key by), so it isn't answered with the server's cover cached for
    /// the book.
    func coverContent(for book: PlayableContent) -> PlayableContent {
        let key = AudiobookProgressStore.key(for: book)
        guard repeatedCovers.contains(key), let found = books[key], let asin = found.asin, let cover = found.cover else { return book }
        return PlayableContent(
            title: book.title,
            subtitle: book.subtitle,
            thumbnail: cover,
            artwork: cover,
            content: .init(service: book.content.service, id: "audible.\(asin)", type: .audiobook, location: nil)
        )
    }

    /// Whether `a` comes before `b` in their series: by their places in it,
    /// a book with none after those with one, else by title. The series
    /// shelf and a series' page both order by it.
    func inSeriesOrder(_ a: PlayableContent, _ b: PlayableContent) -> Bool {
        switch (details(for: a)?.place, details(for: b)?.place) {
        case let (x?, y?) where x != y: x < y
        case (_?, nil): true
        case (nil, _?): false
        default: a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    /// Who reads `book`, names joined, when that's known.
    func narrator(for book: PlayableContent) -> String? {
        guard let narrators = details(for: book)?.narrators, !narrators.isEmpty else { return nil }
        return narrators.formatted(.list(type: .and))
    }

    // MARK: - Audiobookshelf

    /// What Audiobookshelf says of the books it just listed.
    func note(_ items: [AudiobookshelfItem]) {
        var changed = false
        for item in items {
            let metadata = item.media?.metadata
            let series = metadata?.seriesName.flatMap(Self.firstSeries)
            let fromServer = Details(
                narrators: (metadata?.narratorName ?? "")
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty },
                series: series.map { Self.seriesName($0.name) },
                sequence: series?.sequence
            )
            let key = AudiobookProgressStore.key(service: .audiobookshelf, id: item.id)
            var details = fromServer
            // None from the server: Audible's, once asked (`request(_:)`),
            // with the edition it matched and its cover.
            if details.narrators.isEmpty, let asked = books[key], asked.checked != nil {
                details.narrators = asked.narrators
                details.checked = asked.checked
                details.asin = asked.asin
                details.cover = asked.cover
            }
            if books[key] != details {
                books[key] = details
                changed = true
            }
        }
        if changed { save() }
    }

    /// The first of Audiobookshelf's series for a book, "Name #2, Other #5"
    /// as it writes them.
    static func firstSeries(_ text: String) -> (name: String, sequence: String?)? {
        guard let first = text.split(separator: ",").first?.trimmingCharacters(in: .whitespaces), !first.isEmpty else { return nil }
        guard let hash = first.range(of: " #", options: .backwards) else { return (first, nil) }
        let name = first[..<hash.lowerBound].trimmingCharacters(in: .whitespaces)
        let sequence = first[hash.upperBound...].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : (name, sequence.isEmpty ? nil : sequence)
    }

    // MARK: - Plex, from Audible

    /// Asks Audible about the Plex books in `books` not known yet, behind
    /// any already asked for.
    func request(_ books: [PlayableContent]) {
        let fresh = books.filter { book in
            guard book.content.type == .audiobook, [.plex, .audiobookshelf].contains(book.content.service) else { return false }
            let key = AudiobookProgressStore.key(for: book)
            guard !asking.contains(key) else { return false }
            if let failed = unansweredAt[key], Date.now.timeIntervalSince(failed) < Self.retryAfter { return false }
            if let known = self.books[key] {
                // Who reads it known, or asked lately.
                guard known.narrators.isEmpty,
                      Date.now.timeIntervalSince(known.checked ?? .distantPast) > Self.recheckAfter else { return false }
            } else if book.content.service == .audiobookshelf {
                // Not listed by the server yet: its own answer comes first.
                return false
            }
            return true
        }
        for book in books where book.content.type == .audiobook {
            seen[AudiobookProgressStore.key(for: book)] = book
        }
        guard !fresh.isEmpty else { return }
        for book in fresh { asking.insert(AudiobookProgressStore.key(for: book)) }
        pending.append(contentsOf: fresh)
        guard worker == nil else { return }
        worker = Task { await work() }
    }

    /// Looks up what's pending, two at a time, then compares covers, and
    /// again for anything asked for meanwhile: a book asked for while the
    /// covers were compared waited behind a worker that had finished.
    private func work() async {
        repeat {
            await lookUpPending()
            await findRepeatedCovers()
        } while !pending.isEmpty
        worker = nil
    }

    private func lookUpPending() async {
        while !pending.isEmpty {
            let batch = Array(pending.prefix(Self.concurrency))
            pending.removeFirst(batch.count)
            await withTaskGroup(of: (String, Details?).self) { group in
                for book in batch {
                    let key = AudiobookProgressStore.key(for: book)
                    group.addTask { (key, await Self.lookUp(book)) }
                }
                for await (key, details) in group {
                    asking.remove(key)
                    // Unanswered: asked again after a while.
                    guard var details else {
                        unansweredAt[key] = .now
                        continue
                    }
                    unansweredAt[key] = nil
                    // A server's own series wins over Audible's.
                    if let known = books[key], known.series != nil {
                        details.series = known.series
                        details.sequence = known.sequence
                    }
                    books[key] = details
                }
            }
            save()
        }
    }

    /// Marks the books whose server's cover is another's in their series:
    /// compared by a fingerprint of each small cover, those that look the
    /// same are one picture, which the earliest of them keeps (it's most
    /// likely that book's own). The others draw their Audible edition's.
    private func findRepeatedCovers() async {
        let bySeries = Dictionary(grouping: seen) { books[$0.key]?.series ?? "" }
        var found: Set<String> = []
        for (series, members) in bySeries where !series.isEmpty && members.count > 1 {
            var prints: [(key: String, place: Double, print: UInt64)] = []
            for (key, book) in members {
                guard let url = book.thumbnail ?? book.artwork else { continue }
                let printKey = "\(key)|\(url.absoluteString)"
                let print: UInt64
                if let known = fingerprints[printKey] {
                    print = known
                } else {
                    guard let measured = await Self.fingerprint(url) else { continue }
                    fingerprints[printKey] = measured
                    print = measured
                }
                prints.append((key, books[key]?.place ?? .infinity, print))
            }
            for entry in prints {
                let alike = prints.filter { ($0.print ^ entry.print).nonzeroBitCount <= 3 }
                guard let earliest = alike.map(\.place).min(), entry.place > earliest else { continue }
                found.insert(entry.key)
            }
        }
        guard found != repeatedCovers else { return }
        Self.log.info("details: \(found.count) covers repeat another in their series")
        repeatedCovers = found
        save()
    }

    /// A 64-bit fingerprint of the picture at `url`: its 8×8 greyscale,
    /// each bit whether a cell is brighter than the average. The same
    /// cover at any size gives (nearly) the same one.
    private nonisolated static func fingerprint(_ url: URL) async -> UInt64? {
        let request = ImageRequest(url: url, processors: [.resize(size: CGSize(width: 32, height: 32), contentMode: .aspectFill)])
        guard let image = try? await ImagePipeline.shared.image(for: request), let cgImage = image.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: 64)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 8,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            return true
        }
        guard drawn else { return nil }
        let average = pixels.reduce(0) { $0 + Int($1) } / 64
        return pixels.enumerated().reduce(UInt64(0)) { $0 | (Int($1.element) > average ? 1 << UInt64($1.offset) : 0) }
    }

    /// What Audible says of `book`: the series from whichever edition names
    /// one, and the narrators of the edition as long as the book, from its
    /// files, in the listener's store, else the UK's or the US's (Stephen
    /// Fry's Harry Potter is only sold in the UK). Nil when Audible or the
    /// book's length couldn't be read; empty details when it has nothing.
    private nonisolated static func lookUp(_ book: PlayableContent) async -> Details? {
        // "…'s Stone, Book 1" finds nothing on Audible; "…'s Stone" does.
        let bare = book.title.replacingOccurrences(of: #",\s*Book\s+[\d.]+.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        let query = AudibleCatalog.searchTitle(bare)
        let author = book.bookAuthor
        guard let duration = await length(of: book) else {
            log.error("details: couldn't read how long \(book.title, privacy: .public) is")
            return nil
        }
        let home = AudibleCatalog.region()
        var details = Details(checked: .now)
        var seriesFound: [AudibleCatalog.Product.Series] = []
        // The title first, then keywords, which find editions the title
        // search misses; in the listener's store, then the UK's or the US's.
        searching: for region in [home] + ["uk", "us"].filter({ $0 != home }) {
            for byKeywords in [false, true] {
                let found = byKeywords
                    ? await AudibleCatalog.search(keywords: [query, author].compactMap { $0 }.joined(separator: " "), region: region)
                    : await AudibleCatalog.search(title: query, author: author, region: region)
                guard let products = found else {
                    log.error("details: couldn't search Audible (\(region, privacy: .public)) for \(query, privacy: .public)")
                    return nil
                }
                if seriesFound.isEmpty { seriesFound = products.flatMap { $0.series ?? [] } }
                if let asin = AudibleCatalog.editions(products, fitting: duration).first,
                   let edition = products.first(where: { $0.asin == asin }) {
                    details.narrators = edition.narrators?.map(\.name) ?? []
                    details.asin = edition.asin
                    details.cover = edition.coverURL
                    if let own = edition.series, !own.isEmpty { seriesFound = own }
                    break searching
                }
            }
        }
        // A book is often in several (Goblet of Fire in "Wizarding World
        // Collection" before "Harry Potter"): the one the title names, else
        // Audible's first.
        let all = seriesFound.compactMap { entry in entry.title.map { (name: seriesName($0), sequence: entry.sequence) } }
        let title = book.title.lowercased()
        if let series = all.first(where: { title.contains($0.name.lowercased()) }) ?? all.first {
            details.series = series.name
            details.sequence = series.sequence
        } else if let fromTitle = titleSeries(book.title) {
            details.series = fromTitle.name
            details.sequence = fromTitle.sequence
        }
        log.info("details: \(query, privacy: .public), \(Int(duration)) s, read by \(details.narrators.isEmpty ? "no edition that long" : details.narrators.joined(separator: ", "), privacy: .public); series \(details.series ?? "-", privacy: .public) #\(details.sequence ?? "-", privacy: .public)")
        return details
    }

    /// How long `book` is: Audiobookshelf lists it with the book, Plex
    /// only with its files.
    private nonisolated static func length(of book: PlayableContent) async -> TimeInterval? {
        if book.content.service == .audiobookshelf {
            return book.metadata?.duration.map { TimeInterval($0.components.seconds) }
        }
        guard let key = book.plexRatingKey,
              let files = await PlexAPI.shared.audiobookParts(ratingKey: key), !files.isEmpty else { return nil }
        let milliseconds = files.compactMap(\.duration).reduce(0, +)
        return milliseconds > 0 ? TimeInterval(milliseconds) / 1000 : nil
    }

    /// The series a title names, as servers keep it there: "The Fellowship
    /// of the Ring: Lord of the Rings, Book 1", "The Two Towers (Lord of
    /// the Rings)".
    nonisolated static func titleSeries(_ title: String) -> (name: String, sequence: String?)? {
        var text = title
        // "(Series, Book 2)" or "(Series)" at the end.
        if let open = text.range(of: " (", options: .backwards), text.hasSuffix(")") {
            text = String(text[open.upperBound..<text.index(before: text.endIndex)])
        } else if let colon = text.range(of: ": ") {
            text = String(text[colon.upperBound...])
        } else {
            return nil
        }
        var sequence: String?
        if let book = text.range(of: ", Book ", options: [.backwards, .caseInsensitive]) {
            sequence = String(text[book.upperBound...]).trimmingCharacters(in: .whitespaces)
            text = String(text[..<book.lowerBound])
        }
        let name = text.trimmingCharacters(in: .whitespaces)
        // Not a subtitle: a series is a few words, and named with a book's
        // number or in brackets. Nor what an edition is ("Unabridged").
        let editions = ["abridged", "edition", "dramati", "full-cast", "full cast", "narrated", "audiobook", "audio book"]
        guard !name.isEmpty, name.split(separator: " ").count <= 6, sequence != nil || title.hasSuffix(")"),
              !editions.contains(where: name.lowercased().contains) else { return nil }
        return (name, sequence)
    }

    /// A series' name without the edition Audible keeps in it: "Harry
    /// Potter (Full-Cast Editions)" and "Harry Potter (Narrated by Stephen
    /// Fry)" are one series on a shelf.
    nonisolated static func seriesName(_ name: String) -> String {
        guard name.hasSuffix(")"), let open = name.range(of: " (", options: .backwards) else { return name }
        let bare = name[..<open.lowerBound].trimmingCharacters(in: .whitespaces)
        return bare.isEmpty ? name : bare
    }

    /// Encoded and written off the main thread (`ShelfCache`).
    private func save() {
        ShelfCache.save(Store(version: Store.currentVersion, books: books, repeatedCovers: repeatedCovers), named: Self.cacheName)
    }
}
