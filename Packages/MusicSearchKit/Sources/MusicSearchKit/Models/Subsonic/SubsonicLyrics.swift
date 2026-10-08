import Foundation

/// OpenSubsonic's `getLyricsBySongId`: one entry per set of lyrics the
/// server holds for the song (a file's own, a sidecar, translations).
struct SubsonicLyricsList: Decodable {
    let structuredLyrics: [SubsonicStructuredLyrics]?
}

struct SubsonicStructuredLyrics: Decodable {
    let lang: String?
    let synced: Bool?
    /// Milliseconds; positive means the words come sooner.
    let offset: Double?
    /// "main", "translation" or "pronunciation" — only sent when asked for
    /// enhanced lyrics, so missing means main.
    let kind: String?
    let line: [Line]?

    struct Line: Decodable {
        /// Milliseconds; missing when the lyrics aren't timed.
        let start: Double?
        let value: String?
    }
}

/// The original `getLyrics`: plain text, found by artist and title.
struct SubsonicLegacyLyrics: Decodable {
    let artist: String?
    let title: String?
    let value: String?
}

extension SubsonicStructuredLyrics {
    var lyrics: Lyrics? {
        let lines = line ?? []
        let shift = (offset ?? 0) / 1000
        if synced == true, lines.contains(where: { $0.start != nil }) {
            var timed: [(start: TimeInterval, text: String)] = []
            var last: TimeInterval = 0
            for line in lines {
                let start = line.start.map { $0 / 1000 - shift } ?? last
                last = start
                timed.append((start, line.value ?? ""))
            }
            return Lyrics.timed(timed, source: .subsonic).flatMap { $0.isEmpty ? nil : $0 }
        }
        // Some servers put a whole LRC file in one plain line.
        let text = lines.compactMap(\.value).joined(separator: "\n")
        return Lyrics.parse(text, source: .subsonic)
    }
}
