#if DEBUG
import Foundation
import MusicSearchKit
import OSLog
import SonosKit

/// What a Plex book's server and files hold about its chapters, for a book
/// that shows none. Debug builds only.
///
/// Launched with `-AudiobookAudit <title>` (e.g. `xcrun simctl launch
/// <device> dance.cue -AudiobookAudit Fellowship`), it finds the Plex books
/// whose title holds that text (`*` for every one) and, for three at most,
/// saves what Plex says about the book and each file with
/// `includeChapters=1`, looks inside each file for chapter marks of every
/// kind (an mp3's ID3 `CHAP` frames; an `.m4b`'s boxes, its chapter track
/// and Nero `chpl` box among them), and loads the book as its page does. A
/// file that won't come is asked for again a few ways (with a range,
/// whole, converted), and `-AudiobookAuditSong <rating key>` asks for a
/// song's beside it. The report goes to Documents/AudiobookAudit/<rating
/// key>, `report.txt` beside the JSON.
@MainActor
enum AudiobookAudit {
    private static let log = Logger(subsystem: "dance.cue", category: "audiobook-audit")

    static func startIfRequested() {
        // `-AudiobookAuditCarPlay YES`: what the car's tabs would list.
        if UserDefaults.standard.bool(forKey: "AudiobookAuditCarPlay") {
            Task { await carPlay() }
        }
        guard let title = UserDefaults.standard.string(forKey: "AudiobookAudit"), !title.isEmpty else { return }
        Task { await run(title: title) }
    }

    /// The books the car would show — on Home's Recently Played, on the
    /// Audiobooks tab's Continue Listening and its shelves — with no car.
    private static func carPlay() async {
        try? await Task.sleep(for: .seconds(5))
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let books = CarPlayLibrary.recents().filter { $0.content.type == .audiobook }
        log.notice("carplay: audiobooks tab \(CarPlayLibrary.showsAudiobooks ? "shown" : "hidden", privacy: .public); recently played books: \(books.map(\.title), privacy: .public)")
        for book in CarPlayLibrary.booksInProgress() {
            let progress = AudiobookProgressStore.shared.progress(for: book)
            log.notice("carplay: continue listening \(book.title, privacy: .public) \(Int((progress?.fraction ?? 0) * 100))% \(progress.flatMap(AudiobookFormat.remaining) ?? "", privacy: .public)")
        }
        let shelves = await CarPlayLibrary.bookShelves()
        for shelf in shelves {
            log.notice("carplay: shelf \(shelf.title, privacy: .public): \(shelf.items.map(\.title), privacy: .public)")
        }
        // `-AudiobookAuditCarPlayPlay <title>`: plays the first book with
        // that in its title as a tap in the car does, then steps its speed.
        guard let title = UserDefaults.standard.string(forKey: "AudiobookAuditCarPlayPlay"),
              let book = shelves.flatMap(\.items).first(where: { $0.title.localizedCaseInsensitiveContains(title) }) else { return }
        do {
            try await CarPlayPlayback.play(book: book)
            let books = AudiobookPlayer.shared
            log.notice("carplay: playing \(LocalPlaybackService.shared.nowPlaying?.title ?? "-", privacy: .public) for \(books.current?.book.title ?? "-", privacy: .public) at \(Int(books.position)) s, \(books.current?.chapters.count ?? 0) chapters")
            CarPlayPlayback.nextBookRate()
            log.notice("carplay: rate now \(books.rate)")
        } catch {
            log.error("carplay: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    private static func run(title: String) async {
        try? await Task.sleep(for: .seconds(5))
        guard let books = await AudiobookLibrary.plexBooks() else {
            log.error("couldn't read the Plex books")
            return
        }
        await auditLibraries(like: books.first?.plexRatingKey)
        let matches = title == "*" ? books : books.filter { $0.title.localizedCaseInsensitiveContains(title) }
        log.notice("\(books.count) Plex books, \(matches.count) with \"\(title, privacy: .public)\" in the title")
        for book in matches.prefix(3) {
            await audit(book)
        }
        await auditAudiobookshelf(title: title)
        if let key = UserDefaults.standard.string(forKey: "AudiobookAuditSong") {
            await control(songKey: key)
        }
        // `-AudiobookAuditOpen YES`: then opens the first one's page.
        if UserDefaults.standard.bool(forKey: "AudiobookAuditOpen"), let book = matches.first {
            Router.main.navigate(to: .audiobookDetail(content: book))
        }
        log.notice("done")
    }

    /// `-AudiobookAuditSong <rating key>`: whether a song's file comes from
    /// the same server, beside a book's that won't.
    private static func control(songKey: String) async {
        guard let song = await PlexAPI.shared.lookupPlexSong(key: songKey)?.metadata?.first, let url = song.streamURL else {
            log.error("song \(songKey, privacy: .public): not found")
            return
        }
        let folder = song.media?.first?.part.first.map { ($0.file as NSString).deletingLastPathComponent } ?? "?"
        log.notice("song \(songKey, privacy: .public): \(song.title, privacy: .public) in \(folder, privacy: .public)")
        for line in await FileProbe.describe(url, ratingKey: songKey) {
            log.notice("song \(songKey, privacy: .public):   \(line, privacy: .public)")
        }
    }

    private static func audit(_ book: PlayableContent) async {
        guard let key = book.plexRatingKey else { return }
        let report = Report(key: key)
        report.line("\(book.title) — rating key \(key)")
        defer { report.write() }
        guard let files = await PlexAPI.shared.audiobookParts(ratingKey: key), let first = files.first?.streamURL else {
            report.line("no files")
            return
        }
        let chapters = [URLQueryItem(name: "includeChapters", value: "1")]
        report.save(await plexJSON("/library/metadata/\(key)", like: first), as: "book.json")
        report.save(await plexJSON("/library/metadata/\(key)/children", query: chapters, like: first), as: "files.json")
        report.line("\(files.count) files")
        for (index, file) in files.prefix(AudiobookChapterReader.fileLimit).enumerated() {
            report.save(await plexJSON("/library/metadata/\(file.ratingKey)", query: chapters, like: first), as: "file-\(index + 1).json")
            let seconds = (file.duration ?? 0) / 1000
            report.line("file \(index + 1): \(file.title), \(seconds) s, .\(file.streamURL?.pathExtension ?? "?"), Plex chapters: \(file.chapters?.count ?? 0)")
            guard let url = file.streamURL else { continue }
            for line in await FileProbe.describe(url, ratingKey: file.ratingKey) {
                report.line("  \(line)")
            }
        }
        guard let audiobook = await AudiobookLibrary.load(book) else {
            report.line("loaded: couldn't")
            return
        }
        let titles = audiobook.chapters.prefix(5).map { "\($0.title) at \(Int($0.start)) s" }
        report.line("loaded: \(audiobook.chapters.count) chapters over \(Int(audiobook.duration)) s: \(titles.joined(separator: "; "))")
    }

    /// The server's libraries — each one's folders, when it was last
    /// scanned and whether it's scanning now — and the albums added last
    /// across them, for a book added on the server that Cue doesn't show.
    /// Asked with the sign-in a book's file carries, so `bookKey` is any
    /// Plex book's.
    private static func auditLibraries(like bookKey: String?) async {
        guard let bookKey, let url = await PlexAPI.shared.audiobookParts(ratingKey: bookKey)?.first?.streamURL else { return }
        let report = Report(key: "libraries")
        defer { report.write() }
        let sections = await plexJSON("/library/sections", like: url)
        report.save(sections, as: "sections.json")
        let directories = (try? JSONSerialization.jsonObject(with: sections ?? Data()) as? [String: Any])
            .flatMap { $0["MediaContainer"] as? [String: Any] }?["Directory"] as? [[String: Any]] ?? []
        let chosen = PlexAPI.shared.chosenAudiobookLibraryKeys
        report.line("libraries chosen as books: \(chosen.map { $0.joined(separator: ", ") } ?? "none chosen, the suggested ones")")
        for directory in directories {
            let key = directory["key"] as? String ?? "?"
            let scanned = (directory["scannedAt"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)).formatted() } ?? "never"
            let folders = (directory["Location"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
            report.line("library \(key) \(directory["title"] as? String ?? "?") (\(directory["type"] as? String ?? "?"), \(directory["agent"] as? String ?? "?")): scanned \(scanned), refreshing \(directory["refreshing"] as? Bool ?? false), folders \(folders)")
        }
        let recent = await plexJSON("/library/recentlyAdded", query: [URLQueryItem(name: "X-Plex-Container-Size", value: "15")], like: url)
        report.save(recent, as: "recentlyAdded.json")
        let items = (try? JSONSerialization.jsonObject(with: recent ?? Data()) as? [String: Any])
            .flatMap { $0["MediaContainer"] as? [String: Any] }?["Metadata"] as? [[String: Any]] ?? []
        for item in items {
            let added = (item["addedAt"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)).formatted() } ?? "?"
            report.line("added \(added): \(item["type"] as? String ?? "?") \(item["title"] as? String ?? "?") by \(item["parentTitle"] as? String ?? "?") in \(item["librarySectionTitle"] as? String ?? "?"), genres \((item["Genre"] as? [[String: Any]] ?? []).compactMap { $0["tag"] as? String })")
        }
    }

    /// The same for the Audiobookshelf books whose title holds `title`:
    /// the server's chapters, whether its last scan found the files, and
    /// what's inside each file, through the signed file URL.
    private static func auditAudiobookshelf(title: String) async {
        let api = AudiobookshelfAPI.shared
        guard let libraries = await api.libraries() else {
            log.notice("audiobookshelf: no libraries (not signed in, or out of reach)")
            return
        }
        for library in libraries where library.isBooks {
            for found in await api.search(libraryID: library.id, query: title).prefix(3) {
                let report = Report(key: "abs-\(found.id)")
                defer { report.write() }
                guard let item = await api.item(id: found.id) else {
                    report.line("audiobookshelf \(found.id): couldn't be read")
                    continue
                }
                let parts = item.partsToPlayable()
                report.line("audiobookshelf: \(item.toPlayable.title) in \(library.name), \(parts.count) files, \(item.media?.chapters?.count ?? 0) chapters from the server, missing: \(item.isMissing ?? false)")
                for (index, part) in parts.prefix(AudiobookChapterReader.fileLimit).enumerated() {
                    report.line("file \(index + 1): \(part.title), \(part.metadata?.audioCodec ?? "?")")
                    guard let url = AudiobookshelfAPI.fileURL(for: part.content.id, fileExtension: part.metadata?.audioCodec) else { continue }
                    for line in await FileProbe.describe(url, ratingKey: nil) {
                        report.line("  \(line)")
                    }
                }
                guard let audiobook = await AudiobookLibrary.load(item.toPlayable) else {
                    report.line("loaded: couldn't")
                    continue
                }
                let titles = audiobook.chapters.prefix(5).map { "\($0.title) at \(Int($0.start)) s" }
                report.line("loaded: \(audiobook.chapters.count) chapters over \(Int(audiobook.duration)) s: \(titles.joined(separator: "; "))")
            }
        }
    }

    /// Plex's answer for `path` as it came, from the server and with the
    /// sign-in a file's stream URL carries.
    private static func plexJSON(_ path: String, query: [URLQueryItem] = [], like streamURL: URL) async -> Data? {
        guard var components = URLComponents(url: streamURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = path
        components.queryItems = query + (components.queryItems ?? []).filter { $0.name == "X-Plex-Token" }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        return try? await URLSession.shared.data(for: request).0
    }

    /// The lines of one book's report, and the files saved beside it.
    @MainActor
    private final class Report {
        let key: String
        private var lines: [String] = []

        init(key: String) {
            self.key = key
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        var folder: URL {
            URL.documentsDirectory.appending(path: "AudiobookAudit/\(key)")
        }

        func line(_ text: String) {
            lines.append(text)
            AudiobookAudit.log.notice("\(self.key, privacy: .public): \(text, privacy: .public)")
        }

        func save(_ data: Data?, as name: String) {
            guard let data else {
                line("\(name): no answer")
                return
            }
            try? data.write(to: folder.appending(path: name))
        }

        func write() {
            try? lines.joined(separator: "\n").appending("\n").write(to: folder.appending(path: "report.txt"), atomically: true, encoding: .utf8)
        }
    }
}

/// Looks inside a media file over HTTP, a range at a time, for what holds
/// chapter marks: an ID3 tag's frames, or an MP4's boxes.
private enum FileProbe {
    static func describe(_ url: URL, ratingKey: String?) async -> [String] {
        guard let (head, total) = await fetch(url, from: 0, count: 64 * 1024) else { return await failure(url, ratingKey: ratingKey) }
        var lines = ["\(total.map { "\($0) bytes" } ?? "size unknown"), starts \(head.prefix(12).map { String(format: "%02x", $0) }.joined())"]
        if head.count >= 10, head[0..<3] == Array("ID3".utf8)[...] {
            lines += await id3(url, head: head)
        } else if head.count >= 8, String(decoding: head[4..<8], as: UTF8.self) == "ftyp", let total {
            lines += await mp4(url, total: total)
        } else {
            lines.append("neither an ID3 tag nor an MP4")
        }
        return lines
    }

    /// `count` bytes from `offset`, and the file's whole size.
    private static func fetch(_ url: URL, from offset: Int, count: Int) async -> (bytes: [UInt8], total: Int?)? {
        var request = URLRequest(url: url)
        request.addValue("bytes=\(offset)-\(offset + count - 1)", forHTTPHeaderField: "Range")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        let total = (http.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last).flatMap { Int($0) }
        return ([UInt8](data.prefix(count)), total)
    }

    /// Why the file wouldn't come: the answer with a range and without, and
    /// with the download flag; only each answer's head is read.
    private static func failure(_ url: URL, ratingKey: String?) async -> [String] {
        var lines = ["couldn't fetch the file"]
        var download = URLComponents(url: url, resolvingAgainstBaseURL: false)
        download?.queryItems?.append(URLQueryItem(name: "download", value: "1"))
        // Plex's converter, for a Plex file.
        let converted = ratingKey.map { PlexAPI.playbackStreamURL(from: url, ratingKey: $0, format: .mp3, bitrate: 128) }
        let attempts: [(name: String, url: URL?, range: Bool)] = [
            ("with a range", url, true),
            ("whole", url, false),
            ("download=1", download?.url, false),
            ("converted", converted, false)
        ]
        for attempt in attempts {
            guard let attemptURL = attempt.url else { continue }
            var request = URLRequest(url: attemptURL)
            if attempt.range { request.addValue("bytes=0-1023", forHTTPHeaderField: "Range") }
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                bytes.task.cancel()
                guard let http = response as? HTTPURLResponse else { continue }
                let headers = ["Content-Type", "Content-Length", "Content-Range", "Accept-Ranges", "X-Plex-Protocol"]
                    .compactMap { name in http.value(forHTTPHeaderField: name).map { "\(name): \($0)" } }
                lines.append("\(attempt.name): HTTP \(http.statusCode) \(headers.joined(separator: ", "))")
            } catch {
                lines.append("\(attempt.name): \(error.localizedDescription)")
            }
        }
        return lines
    }

    // MARK: ID3

    private static func id3(_ url: URL, head: [UInt8]) async -> [String] {
        let version = head[3]
        let size = syncsafe(head[6..<10])
        let end = 10 + size
        var tag = head
        if end > tag.count, let whole = await fetch(url, from: 0, count: min(end, 16 * 1024 * 1024)) {
            tag = whole.bytes
        }
        guard version >= 3 else { return ["ID3v2.\(version), \(size) bytes (three-letter frames, not read)"] }
        var position = 10
        if head[5] & 0x40 != 0, tag.count >= 14 {
            position += version == 4 ? syncsafe(tag[10..<14]) : 4 + be(tag[10..<14])
        }
        var frames: [String: Int] = [:]
        var order: [String] = []
        var chapters: [String] = []
        while position + 10 <= min(end, tag.count), tag[position] != 0 {
            let id = String(decoding: tag[position..<position + 4], as: UTF8.self)
            let length = version == 4 ? syncsafe(tag[position + 4..<position + 8]) : be(tag[position + 4..<position + 8])
            let body = position + 10
            if frames[id] == nil { order.append(id) }
            frames[id, default: 0] += 1
            if id == "CHAP", body + length <= tag.count, chapters.count < 5 {
                chapters.append(chap(Array(tag[body..<body + length]), version: version))
            }
            position = body + length
        }
        var lines = ["ID3v2.\(version), \(size) bytes, frames: " + order.map { "\($0)×\(frames[$0]!)" }.joined(separator: " ")]
        if !chapters.isEmpty {
            lines.append("CHAP: " + chapters.joined(separator: "; "))
        }
        return lines
    }

    /// A `CHAP` frame: its element id, start and end in milliseconds, then
    /// frames of its own, the title (`TIT2`) among them.
    private static func chap(_ frame: [UInt8], version: UInt8) -> String {
        guard let zero = frame.firstIndex(of: 0), zero + 17 <= frame.count else { return "?" }
        let start = be(frame[zero + 1..<zero + 5])
        let end = be(frame[zero + 5..<zero + 9])
        var position = zero + 17
        var title = ""
        while position + 10 <= frame.count {
            let id = String(decoding: frame[position..<position + 4], as: UTF8.self)
            let length = version == 4 ? syncsafe(frame[position + 4..<position + 8]) : be(frame[position + 4..<position + 8])
            let body = position + 10
            if id == "TIT2", length > 1, body + length <= frame.count {
                title = text(Array(frame[body..<body + length]))
            }
            position = body + length
        }
        return "\"\(title)\" \(start / 1000)–\(end / 1000) s"
    }

    private static func text(_ field: [UInt8]) -> String {
        let bytes = Array(field.dropFirst())
        switch field[0] {
        case 1: return String(data: Data(bytes), encoding: .utf16) ?? "?"
        case 2: return String(data: Data(bytes), encoding: .utf16BigEndian) ?? "?"
        case 3: return String(decoding: bytes, as: UTF8.self)
        default: return String(data: Data(bytes), encoding: .isoLatin1) ?? "?"
        }
    }

    // MARK: MP4

    private static func mp4(_ url: URL, total: Int) async -> [String] {
        var boxes: [(type: String, offset: Int, size: Int)] = []
        var offset = 0
        while offset + 8 <= total, boxes.count < 64 {
            guard let (header, _) = await fetch(url, from: offset, count: 16), header.count >= 8 else { break }
            var size = be(header[0..<4])
            let type = String(decoding: header[4..<8], as: UTF8.self)
            if size == 1, header.count >= 16 { size = be(header[8..<16]) }
            if size == 0 { size = total - offset }
            boxes.append((type, offset, size))
            guard size >= 8 else { break }
            offset += size
        }
        var lines = ["boxes: " + boxes.map { "\($0.type) \($0.size) at \($0.offset)" }.joined(separator: ", ")]
        guard let moov = boxes.first(where: { $0.type == "moov" }) else { return lines + ["no moov"] }
        guard let (bytes, _) = await fetch(url, from: moov.offset, count: min(moov.size, 48 * 1024 * 1024)) else {
            return lines + ["couldn't fetch moov"]
        }
        lines.append("moov: " + tree(bytes, from: 8, to: bytes.count))
        return lines
    }

    private static let containers: Set<String> = ["moov", "trak", "mdia", "minf", "udta", "tref", "edts", "dinf"]

    /// The boxes in `bytes[from..<to]`, descending into those that hold
    /// boxes, with what tells chapters apart: a track's handler, the tracks
    /// a `chap` reference names, and a Nero `chpl` box's marks.
    private static func tree(_ bytes: [UInt8], from: Int, to: Int) -> String {
        var parts: [String] = []
        var position = from
        while position + 8 <= to {
            var size = be(bytes[position..<position + 4])
            let type = String(decoding: bytes[position + 4..<position + 8], as: UTF8.self)
            var header = 8
            if size == 1, position + 16 <= to { size = be(bytes[position + 8..<position + 16]); header = 16 }
            if size == 0 { size = to - position }
            guard size >= header, position + size <= to else {
                parts.append("\(type)(cut short)")
                break
            }
            let body = position + header
            let end = position + size
            switch type {
            case _ where containers.contains(type):
                parts.append("\(type)[\(tree(bytes, from: body, to: end))]")
            case "meta":
                parts.append("meta[\(tree(bytes, from: body + 4, to: end))]")
            case "ilst":
                parts.append("ilst[\(tree(bytes, from: body, to: end).split(separator: ",").count) tags]")
            case "hdlr" where body + 12 <= end:
                parts.append("hdlr(\(String(decoding: bytes[body + 8..<body + 12], as: UTF8.self)))")
            case "chap":
                let ids = stride(from: body, to: end - 3, by: 4).map { be(bytes[$0..<$0 + 4]) }
                parts.append("chap→\(ids)")
            case "chpl":
                parts.append(chpl(Array(bytes[body..<end])))
            case "stbl", "mdat", "free":
                parts.append("\(type) \(size)")
            default:
                parts.append(type)
            }
            position = end
        }
        return parts.joined(separator: ", ")
    }

    /// A Nero chapter list: version and flags, four reserved bytes from
    /// version 1, a count, then each mark's start in 100 ns and its title.
    private static func chpl(_ body: [UInt8]) -> String {
        guard body.count >= 5 else { return "chpl(empty)" }
        var position = body[0] == 0 ? 4 : 8
        guard position < body.count else { return "chpl(cut short)" }
        let count = Int(body[position])
        position += 1
        var marks: [String] = []
        while marks.count < count, position + 9 <= body.count {
            let start = be(body[position..<position + 8]) / 10_000_000
            let length = Int(body[position + 8])
            position += 9
            guard position + length <= body.count else { break }
            if marks.count < 4 {
                marks.append("\"\(String(decoding: body[position..<position + length], as: UTF8.self))\" at \(start) s")
            } else {
                marks.append("")
            }
            position += length
        }
        return "chpl(\(count) marks, read \(marks.count): \(marks.filter { !$0.isEmpty }.joined(separator: "; ")))"
    }

    // MARK: Numbers

    private static func be(_ bytes: ArraySlice<UInt8>) -> Int {
        bytes.reduce(0) { $0 << 8 | Int($1) }
    }

    private static func syncsafe(_ bytes: ArraySlice<UInt8>) -> Int {
        bytes.reduce(0) { $0 << 7 | Int($1 & 0x7f) }
    }
}
#endif
