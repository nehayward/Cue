import AVFoundation
import Foundation
import MusicSearchKit
import Observation
import OSLog
import WatchSync

/// What the watch keeps of each book besides its files: where the listener
/// is, its chapters, and the speed it plays at.
///
/// The place moves as the book plays here (`WatchPlayer`), when the
/// iPhone's context brings a newer one, and when the book's server has one
/// clearly newer than both — another player's — by the iPhone's own rules
/// (`PlexAudiobook.preferring`, `AudiobookProgress.preferring`), so a Plex
/// file only counted played doesn't move it. The iPhone hears the places of
/// the books picked for the watch with the picks (`placesToShare`), and
/// picks a book up where the watch left it, telling the server when it next
/// opens the book.
///
/// Chapters come with the book's files from the server (the marks in a
/// Plex `.m4b`, Audiobookshelf's own), else from the files themselves once
/// they're all here (`readChaptersIfNeeded`). Kept in Application Support,
/// in books.json.
@MainActor
@Observable
final class WatchBookStore {
    static let shared = WatchBookStore()

    private(set) var places: WatchBookPlaces
    /// Each book's chapters as last found, a book of one file without
    /// marks as only itself.
    private(set) var chaptersByBook: [String: [AudiobookChapter]]
    /// Each book's speed, for those not at 1×.
    private(set) var rates: [String: Double]

    /// The speeds offered, as on the iPhone.
    static let rateChoices: [Double] = [0.75, 1, 1.25, 1.5, 1.75, 2]

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    /// Books whose files have been read for chapters this launch.
    @ObservationIgnored private var readFiles: Set<String> = []
    @ObservationIgnored private let logger = Logger(subsystem: "dance.cue.watch", category: "Books")

    private init() {
        let saved = Self.load()
        places = saved.places
        chaptersByBook = saved.chapters
        rates = saved.rates
    }

    // MARK: - Places

    func progress(for key: String) -> AudiobookProgress? {
        places[key].map { AudiobookProgress($0) }
    }

    /// The places of the books picked for the watch: what the iPhone hears.
    var placesToShare: WatchBookPlaces {
        places.restricted(to: Set(WatchDownloadStore.shared.books.map(\.key)))
    }

    /// Keeps a place listening here reached. The iPhone hears of it a while
    /// after (`tellPhone`), or at once on a pause.
    func record(_ progress: AudiobookProgress, for key: String, tellPhoneNow: Bool = false) {
        let changed = places.record(WatchBookPlace(progress), for: key)
        if changed {
            scheduleSave()
        }
        if changed || tellPhoneNow {
            tellPhone(now: tellPhoneNow)
        }
    }

    /// The iPhone's places, merged in. True when it should hear back:
    /// it's missing a place of ours, or ours is newer.
    func apply(_ theirs: WatchBookPlaces) -> Bool {
        let merged = places.merged(with: theirs)
        if merged != places {
            places = merged
            scheduleSave()
        }
        return placesToShare.hasNews(for: theirs)
    }

    /// A book looked up on its server: its chapters, when they were asked
    /// for and say more than those held (a read that lost the marks keeps
    /// the last), and the server's place where it's clearly newer.
    func noteLookedUp(_ book: WatchBookLookup, for pick: WatchPick) {
        if let found = book.chapters, found.count > 1 || (chaptersByBook[pick.key]?.count ?? 0) <= 1, found != chaptersByBook[pick.key] {
            chaptersByBook[pick.key] = found
            scheduleSave()
        }
        guard let server = book.serverPlace else { return }
        let local = progress(for: pick.key)
        let timeline = AudiobookTimeline(partDurations: book.songs.map { $0.duration ?? 0 })
        let preferred = pick.source == .plex
            ? PlexAudiobook.preferring(local: local, server: server, timeline: timeline)
            : AudiobookProgress.preferring(local: local, server: server)
        guard preferred == server, server != local else { return }
        logger.info("\(pick.title, privacy: .public): the server's place, \(Int(server.position)) s, is newer")
        record(server, for: pick.key)
    }

    /// Whether a book's chapters are still to be asked for: none held, or
    /// only the book itself.
    func needsChapters(for key: String) -> Bool {
        (chaptersByBook[key]?.count ?? 0) <= 1
    }

    /// The book's chapters, when it has more than itself.
    func chapters(for key: String) -> [AudiobookChapter] {
        let list = chaptersByBook[key] ?? []
        return list.count > 1 ? list : []
    }

    /// The book's files laid end to end, by the lengths its server gives
    /// them: book time on the watch is the same as on the iPhone.
    func timeline(for key: String) -> AudiobookTimeline {
        AudiobookTimeline(partDurations: WatchDownloadStore.shared.songs(in: [key]).map { $0.duration ?? 0 })
    }

    // MARK: - Speed

    func rate(for key: String) -> Double {
        rates[key] ?? 1
    }

    func setRate(_ rate: Double, for key: String) {
        rates[key] = rate == 1 ? nil : rate
        scheduleSave()
    }

    // MARK: - Picks

    /// Books taken off the watch take their chapters and speed with them.
    /// Their places stay, small as they are, so a book put back picks up
    /// where it was.
    func picksDidChange() {
        let books = Set(WatchDownloadStore.shared.books.map(\.key))
        let keptChapters = chaptersByBook.filter { books.contains($0.key) }
        let keptRates = rates.filter { books.contains($0.key) }
        guard keptChapters.count != chaptersByBook.count || keptRates.count != rates.count else { return }
        chaptersByBook = keptChapters
        rates = keptRates
        scheduleSave()
    }

    // MARK: - Chapters from the files

    /// Reads a book's chapters from its own files once they're all here,
    /// for a book its server gave none for: an `.m4b` whose marks Plex
    /// didn't read at its scan, say. Once a launch.
    func readChaptersIfNeeded(for key: String) {
        guard needsChapters(for: key), !readFiles.contains(key) else { return }
        let store = WatchDownloadStore.shared
        let songs = store.songs(in: [key])
        guard !songs.isEmpty, songs.allSatisfy({ store.isDownloaded($0.key) }) else { return }
        let urls = songs.compactMap { store.localURL(for: $0) }
        guard urls.count == songs.count else { return }
        readFiles.insert(key)
        let titles = songs.map(\.title)
        let timeline = AudiobookTimeline(partDurations: songs.map { $0.duration ?? 0 })
        Task {
            var marks: [[AudiobookChapterMark]] = []
            for url in urls {
                marks.append(await Self.marks(in: url))
            }
            let files = zip(titles, marks).map { (title: $0, marks: $1) }
            let found = [AudiobookChapter].from(files: files, timeline: timeline)
            guard found.count > 1, needsChapters(for: key) else { return }
            logger.info("\(found.count) chapters read from the files of \(key, privacy: .public)")
            chaptersByBook[key] = found
            scheduleSave()
        }
    }

    /// The chapter marks in a file (an `.m4b`'s, an mp3's `CHAP` frames),
    /// as AVFoundation reads them.
    private nonisolated static func marks(in url: URL) async -> [AudiobookChapterMark] {
        let asset = AVURLAsset(url: url)
        guard let groups = try? await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: Locale.preferredLanguages) else { return [] }
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

    // MARK: - Telling the iPhone

    /// Sends the places with the picks: at once for a pause, else a minute
    /// after the first change since the last send, so listening doesn't
    /// send every few seconds.
    private func tellPhone(now: Bool) {
        if now {
            sendTask?.cancel()
            sendTask = nil
            PhoneConnection.shared.send()
            return
        }
        guard sendTask == nil else { return }
        sendTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self else { return }
            self.sendTask = nil
            PhoneConnection.shared.send()
        }
    }

    /// Cue leaving the screen: what's held is written, and the iPhone hears
    /// of a place still waiting to go.
    func flush() {
        if sendTask != nil {
            tellPhone(now: true)
        }
        saveNow()
    }

    // MARK: - Storage

    private struct Saved: Codable {
        var places: WatchBookPlaces
        var chapters: [String: [AudiobookChapter]]
        var rates: [String: Double]
    }

    private static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("books.json")
    }

    private static func load() -> Saved {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else {
            return Saved(places: .empty, chapters: [:], rates: [:])
        }
        return saved
    }

    /// A while after the first change, not after every one: a playing book
    /// records every few seconds.
    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            self.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let data = try? JSONEncoder().encode(Saved(places: places, chapters: chaptersByBook, rates: rates)) else { return }
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

extension WatchBookPlace {
    init(_ progress: AudiobookProgress) {
        self.init(position: progress.position, duration: progress.duration, isFinished: progress.isFinished, updatedAt: progress.updatedAt)
    }
}

extension AudiobookProgress {
    init(_ place: WatchBookPlace) {
        self.init(position: place.position, duration: place.duration, isFinished: place.isFinished, updatedAt: place.updatedAt)
    }
}
