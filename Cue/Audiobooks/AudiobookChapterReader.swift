import AVFoundation
import Foundation
import MusicSearchKit

/// Chapter marks read from a book's file itself — an `.m4b`'s chapter
/// track — for a server that didn't list them: Plex lists an `.m4b`'s
/// chapters only when it read them at scan, and Audiobookshelf only when
/// ffprobe found them. AVFoundation reads the marks over HTTP with a few
/// range requests, not the whole file.
///
/// What a file gave is kept in Caches (`AudiobookChapters.json`), so a book
/// opened again doesn't fetch them again; a file that had none is kept too.
@MainActor
enum AudiobookChapterReader {
    /// Up to this many files, a book's files are read for marks: more is a
    /// file per chapter, and the files are its chapters.
    static let fileLimit = 8

    /// How long one file gets before it counts as having none.
    static let timeout: Duration = .seconds(12)

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
            if let cached = cache[file.key] {
                if !cached.isEmpty { found[file.key] = cached }
            } else if let url = file.url {
                toRead.append((key: file.key, url: url))
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
            cache[file.key] = marks
            if !marks.isEmpty { found[file.key] = marks }
        }
        save()
        return found
    }

    /// The read, or nil once `timeout` has passed, whichever comes first:
    /// a read that won't stop when cancelled doesn't hold the book up.
    private static func readWithTimeout(_ url: URL) async -> [AudiobookChapterMark]? {
        let reading = Task.detached { try? await read(url) }
        let answer = FirstAnswer<[AudiobookChapterMark]?>()
        return await withCheckedContinuation { continuation in
            answer.continuation = continuation
            Task { answer.give(await reading.value) }
            Task {
                try? await Task.sleep(for: timeout)
                reading.cancel()
                answer.give(nil)
            }
        }
    }

    /// The file's chapters in the listener's languages, else in any its
    /// chapter track has (a chapter track is often marked undetermined,
    /// which no preferred language matches).
    private nonisolated static func read(_ url: URL) async throws -> [AudiobookChapterMark] {
        let asset = AVURLAsset(url: url)
        var groups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: Locale.preferredLanguages)
        if groups.isEmpty, let locale = try await asset.load(.availableChapterLocales).first {
            groups = try await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [])
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
        return marks
    }

    // MARK: - Cache

    private static var cache: [String: [AudiobookChapterMark]] = load()

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "AudiobookChapters.json")
    }

    private static func load() -> [String: [AudiobookChapterMark]] {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode([String: [AudiobookChapterMark]].self, from: data) else { return [:] }
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
