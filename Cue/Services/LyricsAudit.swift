#if DEBUG
import Foundation
import MusicSearchKit
import OSLog
import SonosKit

/// Checks lyrics lookups across the Plex library, for finding where they go
/// wrong at scale rather than one song at a time. Debug builds only.
///
/// Launched with `-LyricsAudit <count>` (e.g. `xcrun simctl launch <device>
/// dance.cue -LyricsAudit 150`), it takes that many songs spread evenly
/// through the library and, for each, records what Plex lists and returns,
/// what LRCLIB matches and how (also with the track's own artist where it
/// isn't the album's), and what `LyricsService` would show. LRCLIB is asked
/// about once a second. The report goes to Documents/LyricsAudit: every row
/// in `report.json`, the counts and the rows worth a look in `summary.txt`.
@MainActor
enum LyricsAudit {
    private static let log = Logger(subsystem: "dance.cue", category: "lyrics-audit")

    static func startIfRequested() {
        // `-LyricsAuditRatingKeys 2661,2684`: just those songs, again.
        if let keys = UserDefaults.standard.string(forKey: "LyricsAuditRatingKeys") {
            Task { await run(ratingKeys: keys.split(separator: ",").map(String.init)) }
            return
        }
        let count = UserDefaults.standard.integer(forKey: "LyricsAudit")
        guard count > 0 else { return }
        Task { await run(sampleSize: count) }
    }

    static func run(ratingKeys: [String]) async {
        try? await Task.sleep(for: .seconds(5))
        var rows: [Row] = []
        for (index, key) in ratingKeys.enumerated() {
            guard let song = await PlexAPI.shared.lookupPlexSong(key: key)?.metadata?.first else {
                log.error("no song \(key, privacy: .public)")
                continue
            }
            let row = await check(song, index: index)
            rows.append(row)
            log.info("\(key, privacy: .public) \(row.title, privacy: .public): plex \(row.plex, privacy: .public), lrclib \(row.lrclib, privacy: .public), shown \(row.shown, privacy: .public)")
            try? await Task.sleep(for: .seconds(1))
        }
        write(rows, total: rows.count)
        log.info("done: \(rows.count) songs")
    }

    struct Row: Codable {
        var index: Int
        var title: String
        var albumArtist: String
        var trackArtist: String?
        var album: String?
        var duration: Double
        var ratingKey: String
        var plexStreams: [String]?
        var plex: String
        var plexCredit: String?
        var lrclib: String
        var lrclibVia: String?
        var lrclibID: Int?
        var lrclibTrack: String?
        var lrclibArtist: String?
        var lrclibAlbum: String?
        var lrclibDurationDelta: Double?
        var lrclibTitleMatches: Bool?
        var lrclibWithTrackArtist: String?
        var shown: String
    }

    static func run(sampleSize: Int) async {
        log.info("starting, \(sampleSize) songs")
        var total: Int?
        for _ in 0..<30 {
            let page = await PlexAPI.shared.songPage(offset: 0, limit: 1)
            if let count = page.total, count > 0 {
                total = count
                break
            }
            try? await Task.sleep(for: .seconds(2))
        }
        guard let total else {
            log.error("no Plex library")
            return
        }
        let count = min(sampleSize, total)
        log.info("library has \(total) songs; checking \(count)")
        var rows: [Row] = []
        for index in 0..<count {
            let offset = index * total / count
            guard let song = await PlexAPI.shared.songPage(offset: offset, limit: 1).songs.first else { continue }
            let row = await check(song, index: index)
            rows.append(row)
            log.info("\(index + 1)/\(count) \(row.title, privacy: .public) — \(row.albumArtist, privacy: .public): plex \(row.plex, privacy: .public), lrclib \(row.lrclib, privacy: .public), shown \(row.shown, privacy: .public)")
            if rows.count % 10 == 0 { write(rows, total: total) }
            try? await Task.sleep(for: .seconds(1))
        }
        write(rows, total: total)
        log.info("done: \(rows.count) songs")
    }

    private static func check(_ song: PlexMetadata, index: Int) async -> Row {
        // The fields playback looks lyrics up with (`LyricsService.find`).
        let item = song.toPlayable
        let title = item.title
        let artist = item.metadata?.artist ?? item.subtitle
        let album = item.metadata?.album
        let duration = Double(song.duration ?? 0) / 1000
        let trackArtist = song.originalTitle.flatMap { $0.isEmpty || $0 == artist ? nil : $0 }
        var row = Row(
            index: index, title: title, albumArtist: artist, trackArtist: trackArtist, album: album,
            duration: duration, ratingKey: song.ratingKey, plex: "", lrclib: "", shown: ""
        )

        row.plexStreams = await PlexAPI.shared.lyricStreamDescriptions(ratingKey: song.ratingKey)
        var plexLyrics: Lyrics?
        do {
            plexLyrics = try await PlexAPI.shared.lyrics(ratingKey: song.ratingKey)
            row.plex = describe(plexLyrics)
            row.plexCredit = plexLyrics?.credit
        } catch {
            row.plex = "error: \(error)"
        }

        var match: LRCLibAPI.Match?
        do {
            match = try await LRCLibAPI.match(title: title, artist: artist, album: album, duration: duration)
            row.lrclib = describe(match?.lyrics)
            if let match {
                row.lrclibVia = match.via
                row.lrclibID = match.id
                row.lrclibTrack = match.trackName
                row.lrclibArtist = match.artistName
                row.lrclibAlbum = match.albumName
                row.lrclibDurationDelta = match.duration.map { ($0 - duration).rounded() }
                row.lrclibTitleMatches = normalized(LRCLibAPI.searchTitle(match.trackName ?? "")) == normalized(LRCLibAPI.searchTitle(title))
            }
        } catch {
            row.lrclib = "error: \(error)"
        }
        if let trackArtist {
            do {
                let other = try await LRCLibAPI.match(title: title, artist: trackArtist, album: album, duration: duration)
                row.lrclibWithTrackArtist = describe(other?.lyrics) + (other.map { " (\($0.via))" } ?? "")
            } catch {
                row.lrclibWithTrackArtist = "error: \(error)"
            }
        }

        // `LyricsService.find`'s choice.
        if let plexLyrics, plexLyrics.isSynced || plexLyrics.isInstrumental {
            row.shown = "plex " + describe(plexLyrics)
        } else if let lyrics = match?.lyrics, lyrics.isSynced || plexLyrics == nil {
            row.shown = "lrclib " + describe(lyrics)
        } else if let plexLyrics {
            row.shown = "plex " + describe(plexLyrics)
        } else {
            row.shown = "none"
        }
        return row
    }

    private static func describe(_ lyrics: Lyrics?) -> String {
        guard let lyrics else { return "none" }
        if lyrics.isInstrumental { return "instrumental" }
        return "\(lyrics.isWordTimed ? "word-timed" : lyrics.isSynced ? "timed" : "plain") \(lyrics.lines.count)"
    }

    private static func normalized(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func write(_ rows: [Row], total: Int) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appendingPathComponent("LyricsAudit", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(rows).write(to: folder.appendingPathComponent("report.json"), options: .atomic)
        try? summary(rows, total: total).write(to: folder.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
    }

    private static func summary(_ rows: [Row], total: Int) -> String {
        func count(_ predicate: (Row) -> Bool) -> Int { rows.filter(predicate).count }
        func kind(_ text: String) -> String { String(text.split(separator: " ").first ?? "") }
        var lines = ["\(rows.count) of \(total) Plex songs", ""]
        let shown = Dictionary(grouping: rows) { row in
            let parts = row.shown.split(separator: " ")
            return parts.prefix(2).joined(separator: " ")
        }
        lines.append("Shown:")
        for (key, group) in shown.sorted(by: { $0.value.count > $1.value.count }) {
            lines.append("  \(key): \(group.count)")
        }
        lines.append("")
        lines.append("Plex: streams listed \(count { ($0.plexStreams?.isEmpty == false) }), none listed \(count { $0.plexStreams?.isEmpty == true }), couldn't list \(count { $0.plexStreams == nil })")
        lines.append("Plex results: " + Dictionary(grouping: rows) { kind($0.plex) }.map { "\($0.key) \($0.value.count)" }.sorted().joined(separator: ", "))
        lines.append("LRCLIB results: " + Dictionary(grouping: rows) { kind($0.lrclib) }.map { "\($0.key) \($0.value.count)" }.sorted().joined(separator: ", "))
        lines.append("LRCLIB via: " + Dictionary(grouping: rows.compactMap(\.lrclibVia)) { $0 }.map { "\($0.key) \($0.value.count)" }.sorted().joined(separator: ", "))
        lines.append("LRCLIB title differs: \(count { $0.lrclibTitleMatches == false }), length off by 2 s or more: \(count { abs($0.lrclibDurationDelta ?? 0) >= 2 })")
        lines.append("Track artist differs from album artist: \(count { $0.trackArtist != nil }); of those, LRCLIB found nothing with the album artist but did with the track's: \(count { $0.trackArtist != nil && kind($0.lrclib) == "none" && !($0.lrclibWithTrackArtist ?? "none").hasPrefix("none") })")

        func section(_ title: String, _ filter: (Row) -> Bool) {
            let matching = rows.filter(filter)
            guard !matching.isEmpty else { return }
            lines.append("")
            lines.append("\(title) (\(matching.count)):")
            for row in matching {
                lines.append("  #\(row.index) \(row.title) — \(row.albumArtist)\(row.trackArtist.map { " [track: \($0)]" } ?? "") · \(Int(row.duration)) s · plex \(row.plex)\(row.plexStreams.map { " \($0)" } ?? "") · lrclib \(row.lrclib)\(row.lrclibVia.map { " via \($0)" } ?? "")\(row.lrclibTrack.map { " → \"\($0)\" by \(row.lrclibArtist ?? "?")" } ?? "")\(row.lrclibDurationDelta.map { " Δ\(Int($0)) s" } ?? "")\(row.lrclibWithTrackArtist.map { " · with track artist: \($0)" } ?? "")")
            }
        }
        section("Plex errors") { $0.plex.hasPrefix("error") }
        section("Plex lists lyrics but returned none") { ($0.plexStreams?.isEmpty == false) && kind($0.plex) == "none" }
        section("LRCLIB matched a different title") { $0.lrclibTitleMatches == false }
        section("Nothing shown") { $0.shown == "none" }
        section("LRCLIB errors") { $0.lrclib.hasPrefix("error") }
        return lines.joined(separator: "\n")
    }
}
#endif
