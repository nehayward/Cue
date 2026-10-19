import AVFoundation
import Foundation
import MusicSearchKit
import OSLog

/// Chapter marks read from a book's file itself — an `.m4b`'s chapter
/// track — for a server that didn't list them: Plex lists an `.m4b`'s
/// chapters only when it read them at scan, and Audiobookshelf only when
/// ffprobe found them. AVFoundation reads the marks over HTTP with a few
/// range requests, not the whole file.
///
/// What a file gave is kept in Caches (`AudiobookChapters-2.json`), so a
/// book opened again doesn't fetch them again. A file that had none is kept
/// for a day (`noneLifetime`), then read again. Each read logs what the
/// file holds under the `audiobooks` category.
@MainActor
enum AudiobookChapterReader {
    /// Up to this many files, a book's files are read for marks: more is a
    /// file per chapter, and the files are its chapters.
    static let fileLimit = 8

    /// How long one file gets before it counts as having none.
    static let timeout: Duration = .seconds(12)

    /// How long "none" is believed before the file is read again.
    static let noneLifetime: TimeInterval = 24 * 60 * 60

    private nonisolated static let log = Logger(subsystem: "dance.cue", category: "audiobooks")

    /// The marks inside each file, by the file's key (the server's id for
    /// it, which also keys the cache). A file that has none, or couldn't be
    /// read in time, is left out.
    static func marks(
        in files: [(key: String, url: URL?)]
    ) async -> [String: [AudiobookChapterMark]] {
        guard files.count <= fileLimit else { return [:] }
        var found: [String: [AudiobookChapterMark]] = [:]
        var toRead: [(key: String, url: URL)] = []
        for file in files {
            if let cached = cached(file.key) {
                if !cached.isEmpty { found[file.key] = cached }
            } else if let url = file.url {
                toRead.append((key: file.key, url: url))
            } else {
                log.error("chapters: no address to read \(file.key, privacy: .public) from")
            }
        }
        guard !toRead.isEmpty else { return found }

        let read = await withTaskGroup(of: (key: String, marks: [AudiobookChapterMark]?).self) { group in
            for file in toRead {
                group.addTask { (key: file.key, marks: await readWithTimeout(file.url)) }
            }
            var read: [(key: String, marks: [AudiobookChapterMark]?)] = []
            for await file in group {
                read.append(file)
            }
            return read
        }
        for file in read {
            // A file that timed out or failed (nil) is tried again next
            // time; one read with no marks is kept as none.
            guard let marks = file.marks else { continue }
            cache[file.key] = Entry(marks: marks)
            if !marks.isEmpty { found[file.key] = marks }
        }
        save()
        return found
    }

    /// The read, or nil once `timeout` has passed, whichever comes first:
    /// a read that won't stop when cancelled doesn't hold the book up.
    private static func readWithTimeout(_ url: URL) async -> [AudiobookChapterMark]? {
        let reading = Task.detached { await read(url) }
        let answer = FirstAnswer<[AudiobookChapterMark]?>()
        return await withCheckedContinuation { continuation in
            answer.continuation = continuation
            Task { answer.give(await reading.value) }
            Task {
                try? await Task.sleep(for: timeout)
                guard answer.continuation != nil else { return }
                log.error("chapters: \(url.lastPathComponent, privacy: .public) timed out")
                reading.cancel()
                answer.give(nil)
            }
        }
    }

    /// The file's chapters in the listener's languages, else in each
    /// language its chapter track has, else undetermined (a chapter track
    /// is often marked so, which no preferred language matches). Nil when
    /// the file couldn't be read. Logs what the file holds — its tracks,
    /// metadata formats and chapter languages — so a book with none can be
    /// told from one Cue couldn't read.
    private nonisolated static func read(_ url: URL) async -> [AudiobookChapterMark]? {
        let name = url.lastPathComponent
        let asset = AVURLAsset(url: url)
        do {
            var groups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: Locale.preferredLanguages)
            let locales = try await asset.load(.availableChapterLocales)
            for locale in locales where groups.isEmpty {
                groups = try await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [])
            }
            if groups.isEmpty {
                groups = try await asset.loadChapterMetadataGroups(withTitleLocale: Locale(identifier: "und"), containingItemsWithCommonKeys: [])
            }
            var marks: [AudiobookChapterMark] = []
            for group in groups {
                let range = group.timeRange
                guard range.start.isNumeric else { continue }
                let titleItem = AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle).first
                let title = try? await titleItem?.load(.stringValue)
                let end = range.duration.isNumeric ? range.end.seconds : nil
                marks.append(AudiobookChapterMark(title: title, start: range.start.seconds, end: end))
            }
            if marks.isEmpty {
                let tracks = (try? await asset.load(.tracks))?.map(\.mediaType.rawValue) ?? []
                let formats = (try? await asset.load(.availableMetadataFormats))?.map(\.rawValue) ?? []
                log.notice("chapters: \(name, privacy: .public) has none (tracks: \(tracks, privacy: .public), metadata: \(formats, privacy: .public), chapter languages: \(locales.map(\.identifier), privacy: .public))")
            } else {
                log.info("chapters: \(name, privacy: .public) has \(marks.count)")
            }
            return marks
        } catch {
            log.error("chapters: couldn't read \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Audible's chapters

    /// Audible's chapters for a book with no marks anywhere, by its ASIN
    /// (`AudnexusChapters`), laid on a book `duration` long. Nil when
    /// Audible has none, or none that fit this edition. `lookup` asks the
    /// book's server or Audnexus; an answer is kept with the files' marks
    /// (none too), and a lookup that couldn't be made is tried next time.
    static func audibleChapters(
        asin: String,
        duration: TimeInterval,
        lookup: () async -> AudnexusChapters?
    ) async -> [AudiobookChapter]? {
        let key = "audnexus:\(asin):\(Int(duration.rounded()))"
        if let cached = cached(key) {
            guard !cached.isEmpty else { return nil }
            return .from(files: [(title: "", marks: cached)], timeline: AudiobookTimeline(partDurations: [duration]))
        }
        guard let answer = await lookup() else {
            log.error("chapters: couldn't ask for Audible's chapters for \(asin, privacy: .public)")
            return nil
        }
        let fitted = answer.chapters(fitting: duration) ?? []
        if fitted.isEmpty {
            let runtime = Int((answer.runtimeLengthMs ?? 0) / 1000)
            let count = answer.chapters?.count ?? 0
            let reason = answer.error ?? ""
            log.notice("chapters: Audible's for \(asin, privacy: .public) don't fit: \(count) chapters over \(runtime) s, the book \(Int(duration)) s \(reason, privacy: .public)")
        }
        cache[key] = Entry(marks: fitted.map { AudiobookChapterMark(title: $0.title, start: $0.start, end: $0.end) })
        save()
        return fitted.isEmpty ? nil : fitted
    }

    /// Audible's chapters for a book no server matched there: its title and
    /// author searched for in Audible's catalog, and the editions as long as
    /// the book (`AudibleCatalog`) fitted as a matched book's are, closest
    /// first. What the search found is kept (none too, for a day); a search
    /// that couldn't be made is tried next time.
    static func searchedAudibleChapters(title: String, author: String?, duration: TimeInterval) async -> [AudiobookChapter]? {
        let region = AudibleCatalog.region()
        let query = AudibleCatalog.searchTitle(title)
        let key = "audible-search:\(region):\(query.lowercased()):\(author?.lowercased() ?? ""):\(Int(duration.rounded()))"
        if let cached = cached(key) {
            guard !cached.isEmpty else { return nil }
            return .from(files: [(title: "", marks: cached)], timeline: AudiobookTimeline(partDurations: [duration]))
        }
        guard let products = await AudibleCatalog.search(title: query, author: author, region: region) else {
            log.error("chapters: couldn't search Audible for \(query, privacy: .public)")
            return nil
        }
        let editions = AudibleCatalog.editions(products, fitting: duration)
        var found: [AudiobookChapter]?
        for asin in editions.prefix(3) {
            found = await audibleChapters(asin: asin, duration: duration) {
                await AudnexusAPI.chapters(asin: asin, region: region)
            }
            if found != nil {
                log.info("chapters: \(query, privacy: .public) is \(asin, privacy: .public) on Audible")
                break
            }
        }
        if found == nil {
            log.notice("chapters: no edition of \(query, privacy: .public) on Audible fits \(Int(duration)) s (\(products.count) found, \(editions.count) about as long)")
        }
        cache[key] = Entry(marks: (found ?? []).map { AudiobookChapterMark(title: $0.title, start: $0.start, end: $0.end) })
        save()
        return found
    }

    // MARK: - Cache

    /// What was read, and when: "none" is believed only for a while.
    private struct Entry: Codable {
        var marks: [AudiobookChapterMark]
        var readAt: Date = .now
    }

    private static var cache: [String: Entry] = load()

    /// The marks kept for `key`; nil when there are none kept, or "none"
    /// has gone stale.
    private static func cached(_ key: String) -> [AudiobookChapterMark]? {
        guard let entry = cache[key] else { return nil }
        if entry.marks.isEmpty, Date.now.timeIntervalSince(entry.readAt) > noneLifetime { return nil }
        return entry.marks
    }

    /// A new name drops what an earlier reader kept, "none"s it may have
    /// got wrong included.
    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "AudiobookChapters-2.json")
    }

    private static func load() -> [String: Entry] {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return cache
    }

    private static func save() {
        guard let url = cacheURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Resumes its continuation with the first value it's given.
@MainActor
private final class FirstAnswer<Value> {
    var continuation: CheckedContinuation<Value, Never>?

    func give(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
