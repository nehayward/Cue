import Foundation
import OSLog

/// A song's words, timed or not, from wherever they were found: the song's
/// own server (Plex, Subsonic), the file itself, or LRCLIB.
///
/// Timed lyrics carry a start for every line, in seconds into the song,
/// already corrected by any offset their source gave; plain lyrics carry
/// none. Some timed lyrics time each word as well (enhanced LRC's
/// `<mm:ss.xx>` stamps, Plex's spans), which the player fills through as
/// they're sung. An empty line is a break — between verses in plain
/// lyrics, an instrumental stretch in timed ones.
public struct Lyrics: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case plex
        case subsonic
        case file
        case lrclib
    }

    public struct Word: Codable, Equatable, Sendable {
        /// Seconds into the song.
        public let start: TimeInterval
        /// As written, with the space after it when there is one.
        public let text: String

        public init(start: TimeInterval, text: String) {
            self.start = start
            self.text = text
        }
    }

    public struct Line: Codable, Equatable, Sendable, Identifiable {
        /// Its place in `lines`.
        public let id: Int
        /// Seconds into the song; `nil` in lyrics that aren't timed.
        public let start: TimeInterval?
        public let text: String
        /// The line word by word, when its source timed them.
        public let words: [Word]?
        /// When the last word ends, when the source says.
        public let end: TimeInterval?

        public var isBreak: Bool { text.isEmpty }
    }

    /// A timed line on its way into `Lyrics.timed`.
    public struct TimedLine: Equatable, Sendable {
        public var start: TimeInterval
        public var text: String
        public var words: [Word]?
        public var end: TimeInterval?

        public init(start: TimeInterval, text: String, words: [Word]? = nil, end: TimeInterval? = nil) {
            self.start = start
            self.text = text
            self.words = words
            self.end = end
        }
    }

    public let lines: [Line]
    public let source: Source
    /// Who the words came from, when the source names someone — Plex's
    /// lyrics agent, for one.
    public let credit: String?
    /// The source says the song has no words.
    public let isInstrumental: Bool

    public init(source: Source, credit: String? = nil, isInstrumental: Bool = false, lines: [(start: TimeInterval?, text: String)]) {
        self.source = source
        self.credit = credit
        self.isInstrumental = isInstrumental
        self.lines = lines.enumerated().map {
            Line(id: $0.offset, start: $0.element.start, text: $0.element.text, words: nil, end: nil)
        }
    }

    private init(source: Source, credit: String?, timedLines: [TimedLine]) {
        self.source = source
        self.credit = credit
        self.isInstrumental = false
        self.lines = timedLines.enumerated().map {
            Line(id: $0.offset, start: $0.element.start, text: $0.element.text, words: $0.element.words, end: $0.element.end)
        }
    }

    public static func instrumental(source: Source, credit: String? = nil) -> Lyrics {
        Lyrics(source: source, credit: credit, isInstrumental: true, lines: [])
    }

    public var isSynced: Bool { lines.first?.start != nil }

    /// Some line is timed word by word.
    public var isWordTimed: Bool { lines.contains { $0.words != nil } }

    /// Nothing to show: no line has any words.
    public var isEmpty: Bool { lines.allSatisfy(\.isBreak) }

    /// The line being sung at `position`: the last one started by then.
    /// `nil` before the first line, and always for lyrics that aren't timed.
    public func lineIndex(at position: TimeInterval) -> Int? {
        guard isSynced else { return nil }
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if (lines[mid].start ?? 0) <= position {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low == 0 ? nil : low - 1
    }

    /// When the line after `index` starts, if there is one.
    public func nextStart(after index: Int) -> TimeInterval? {
        lines.indices.contains(index + 1) ? lines[index + 1].start : nil
    }
}

/// A lyrics source that couldn't be asked — unreachable, or an error from
/// the server — as against one that answered with none.
public struct LyricsLookupError: Error, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }

    /// Where lyrics lookups log, in whichever app they run.
    static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MusicSearchKit", category: "lyrics")
}

// MARK: - Progress through a line

extension Lyrics.Line {
    /// Seconds a character takes to sing, for lines whose words aren't
    /// timed: about thirteen a second, a usual pace for sung English.
    static let secondsPerCharacter: TimeInterval = 0.075

    /// How much of the line has been sung at `position`, as a fraction of
    /// its characters. By its words when they're timed — through each word
    /// evenly — and otherwise spread over the time until `nextStart`, cut
    /// short to a usual singing pace so a line followed by a long gap isn't
    /// still filling through the gap.
    public func progress(at position: TimeInterval, nextStart: TimeInterval?) -> Double {
        guard let start, !text.isEmpty else { return 0 }
        guard position > start else { return 0 }

        if let words, !words.isEmpty {
            let total = words.reduce(0) { $0 + $1.text.count }
            guard total > 0 else { return 1 }
            guard let index = words.lastIndex(where: { $0.start <= position }) else { return 0 }
            let word = words[index]
            let before = words[..<index].reduce(0) { $0 + $1.text.count }
            let wordEnd = index + 1 < words.count
                ? words[index + 1].start
                : end ?? min(nextStart ?? .infinity, word.start + paced(word.text.count))
            let fraction = wordEnd > word.start ? min(1, (position - word.start) / (wordEnd - word.start)) : 1
            return min(1, (Double(before) + fraction * Double(word.text.count)) / Double(total))
        }

        let paced = paced(text.count)
        let duration = min(paced, (nextStart ?? .infinity) - start)
        guard duration > 0 else { return 1 }
        return min(1, (position - start) / duration)
    }

    private func paced(_ characters: Int) -> TimeInterval {
        max(0.8, Double(characters) * Self.secondsPerCharacter + 0.3)
    }
}

// MARK: - Building

extension Lyrics {
    /// Timed lines in any order, with breaks tidied: sorted by start, a run
    /// of breaks kept as one, and none left at the end.
    public static func timed(_ lines: [(start: TimeInterval, text: String)], source: Source, credit: String? = nil) -> Lyrics? {
        timed(lines: lines.map { TimedLine(start: $0.start, text: $0.text) }, source: source, credit: credit)
    }

    public static func timed(lines: [TimedLine], source: Source, credit: String? = nil) -> Lyrics? {
        var tidy: [TimedLine] = []
        let sorted = lines.enumerated().sorted { lhs, rhs in
            // Stable: two lines stamped alike keep the order they came in.
            lhs.element.start == rhs.element.start ? lhs.offset < rhs.offset : lhs.element.start < rhs.element.start
        }
        for (_, line) in sorted {
            var line = line
            line.text = line.text.trimmingCharacters(in: .whitespaces)
            line.start = max(0, line.start)
            if line.text.isEmpty {
                if tidy.last?.text.isEmpty ?? true { continue }
                line.words = nil
            }
            tidy.append(line)
        }
        while tidy.last?.text.isEmpty == true { tidy.removeLast() }
        guard !tidy.isEmpty else { return nil }
        return Lyrics(source: source, credit: credit, timedLines: tidy)
    }

    /// Plain lines with breaks tidied: none at either end, and a run of
    /// them kept as one.
    public static func plain(_ lines: [String], source: Source, credit: String? = nil) -> Lyrics? {
        var tidy: [(start: TimeInterval?, text: String)] = []
        for line in lines {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty, tidy.last?.text.isEmpty ?? true { continue }
            tidy.append((nil, text))
        }
        while tidy.last?.text.isEmpty == true { tidy.removeLast() }
        guard !tidy.isEmpty else { return nil }
        return Lyrics(source: source, credit: credit, lines: tidy)
    }

    /// Reads LRC — `[mm:ss.xx]` before each line, several stamps on a line
    /// sung more than once, `[offset:]` in milliseconds (positive is
    /// sooner), and enhanced LRC's word stamps (`<mm:ss.xx>` before each
    /// word) — or, when no line has a stamp, plain text a line at a time.
    /// `nil` when there are no words.
    public static func parse(_ text: String, source: Source, credit: String? = nil) -> Lyrics? {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var offset: TimeInterval = 0
        var timed: [TimedLine] = []
        var plain: [String] = []

        lines: for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            var rest = raw.drop { $0.isWhitespace }
            var stamps: [TimeInterval] = []
            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let stamp = timestamp(tag) {
                    stamps.append(stamp)
                } else if stamps.isEmpty, let idTag = idTag(tag) {
                    // `[ar:…]`, `[ti:…]`, `[length:…]` and the like say
                    // something about the song, not a line of it.
                    if idTag.key == "offset", let milliseconds = Double(idTag.value.trimmingCharacters(in: .whitespaces)) {
                        offset = milliseconds / 1000
                    }
                    continue lines
                } else {
                    // "[Chorus]" in plain lyrics: words, not a tag.
                    break
                }
                rest = rest[rest.index(after: close)...]
            }
            let line = String(rest)
            if stamps.isEmpty {
                plain.append(stripWordStamps(line).trimmingCharacters(in: .whitespaces))
                continue
            }
            // Word stamps are times in the song, so they only belong to a
            // line sung once.
            let timedWords = stamps.count == 1 ? wordStamps(in: line, lineStart: stamps[0]) : nil
            let words = timedWords.map { $0.words.isEmpty ? nil : $0.words } ?? nil
            let lineText = words.map { $0.map(\.text).joined() } ?? stripWordStamps(line)
            for stamp in stamps {
                timed.append(TimedLine(start: stamp, text: lineText, words: words, end: timedWords?.end))
            }
        }

        if !timed.isEmpty {
            let shifted = timed.map { line in
                TimedLine(
                    start: line.start - offset,
                    text: line.text,
                    words: line.words?.map { Word(start: max(0, $0.start - offset), text: $0.text) },
                    end: line.end.map { $0 - offset }
                )
            }
            if let lyrics = Self.timed(lines: shifted, source: source, credit: credit), !lyrics.isEmpty {
                return lyrics
            }
            return nil
        }
        guard let lyrics = Self.plain(plain, source: source, credit: credit), !lyrics.isEmpty else { return nil }
        return lyrics
    }

    /// `mm:ss`, `mm:ss.x` to `mm:ss.xxx`, and `mm:ss:xx`, which some
    /// writers use for hundredths.
    static func timestamp(_ tag: Substring) -> TimeInterval? {
        guard let match = tag.wholeMatch(of: #/(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?/#),
              let minutes = Double(match.1), let seconds = Double(match.2) else { return nil }
        let fraction = match.3.flatMap { Double("0.\($0)") } ?? 0
        return minutes * 60 + seconds + fraction
    }

    private static let wordStamp = #/<(\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?)>/#

    /// A line's words from enhanced LRC: each `<mm:ss.xx>` starts the text
    /// up to the next one, and a stamp with nothing after it ends the line.
    /// Text before the first stamp starts with the line. `nil` when the
    /// line has no word stamps.
    static func wordStamps(in line: String, lineStart: TimeInterval) -> (words: [Word], end: TimeInterval?)? {
        let matches = line.matches(of: wordStamp)
        guard !matches.isEmpty else { return nil }
        var words: [Word] = []
        var end: TimeInterval?
        let lead = String(line[..<matches[0].range.lowerBound])
        if !lead.trimmingCharacters(in: .whitespaces).isEmpty {
            words.append(Word(start: lineStart, text: lead.drop { $0.isWhitespace }.description))
        }
        for (index, match) in matches.enumerated() {
            guard let start = timestamp(match.output.1) else { continue }
            let textEnd = index + 1 < matches.count ? matches[index + 1].range.lowerBound : line.endIndex
            let text = String(line[match.range.upperBound..<textEnd])
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                if index == matches.count - 1 {
                    end = start
                } else if let last = words.popLast() {
                    // A stamp on a space: it belongs to the word before.
                    words.append(Word(start: last.start, text: last.text + text))
                }
                continue
            }
            words.append(Word(start: start, text: words.isEmpty ? String(text.drop { $0.isWhitespace }) : text))
        }
        // The line's own text is trimmed; so is its last word.
        if let last = words.popLast() {
            words.append(Word(start: last.start, text: last.text.replacing(#/\s+$/#, with: "")))
        }
        return (words, end)
    }

    private static func idTag(_ tag: Substring) -> (key: String, value: Substring)? {
        guard let colon = tag.firstIndex(of: ":") else { return nil }
        let key = tag[..<colon]
        guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0 == "#" }) else { return nil }
        return (key.lowercased(), tag[tag.index(after: colon)...])
    }

    private static func stripWordStamps(_ text: String) -> String {
        guard text.contains("<") else { return text }
        return text.replacing(wordStamp, with: "")
    }
}
