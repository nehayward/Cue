import Foundation

/// What's said in one of a book's files, as the on-device transcriber heard
/// it (`BookTranscriber`): lines of about a sentence, each with when it
/// starts and ends on the file's clock, and its words with theirs.
///
/// `covered` is what of the file has been transcribed, so a file read ahead
/// once isn't read again: the transcript is kept in Caches by the file
/// (`BookTranscriptStore`), and a book picked up later opens on it.
struct BookTranscript: Codable, Equatable, Sendable {
    struct Word: Codable, Equatable, Sendable {
        /// The word with the space or punctuation before it, as the
        /// transcriber wrote it.
        let text: String
        /// File time it's said at, when the transcriber knew.
        let start: TimeInterval?
    }

    struct Line: Codable, Equatable, Identifiable, Sendable {
        var id: TimeInterval { start }
        let start: TimeInterval
        let end: TimeInterval
        let words: [Word]

        var text: String {
            words.map(\.text).joined().trimmingCharacters(in: .whitespaces)
        }
    }

    /// In order, none overlapping.
    private(set) var lines: [Line] = []
    /// Stretches of the file transcribed, in order, none overlapping.
    private(set) var covered: [ClosedRange<TimeInterval>] = []

    /// Adds `new`, in place of any lines it overlaps: a stretch heard
    /// again replaces what was heard before.
    mutating func insert(_ new: [Line]) {
        guard let first = new.first?.start, let last = new.last?.end else { return }
        lines.removeAll { $0.end > first && $0.start < last }
        let index = lines.firstIndex { $0.start >= first } ?? lines.endIndex
        lines.insert(contentsOf: new, at: index)
    }

    /// Notes `range` as transcribed.
    mutating func cover(_ range: ClosedRange<TimeInterval>) {
        var merged = range
        covered.removeAll { other in
            guard other.lowerBound <= merged.upperBound + 1, merged.lowerBound <= other.upperBound + 1 else { return false }
            merged = min(merged.lowerBound, other.lowerBound)...max(merged.upperBound, other.upperBound)
            return true
        }
        let index = covered.firstIndex { $0.lowerBound > merged.lowerBound } ?? covered.endIndex
        covered.insert(merged, at: index)
    }

    /// The first time at or after `time` not transcribed yet.
    func firstUncovered(from time: TimeInterval) -> TimeInterval {
        var time = time
        for range in covered where range.contains(time) {
            time = range.upperBound
        }
        return time
    }

    /// The line being said at `time`: the last that starts at or before it.
    func lineIndex(at time: TimeInterval) -> Int? {
        var low = 0, high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].start <= time { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? low - 1 : nil
    }
}

extension BookTranscript {
    /// Splits a result's words into lines of about a sentence: after a
    /// word that ends one, or at a comma once a line runs long, or at any
    /// word once it runs very long. `end` is where the result ends, the
    /// last line's end.
    static func lines(from words: [Word], fallbackStart: TimeInterval, end: TimeInterval) -> [Line] {
        // The model now and then hears a burst of noise as a run of dots:
        // kept to one, and a line of nothing else left out below.
        let words = words.compactMap { word -> Word? in
            var text = word.text
            while text.contains("..") { text = text.replacingOccurrences(of: "..", with: ".") }
            return text.isEmpty ? nil : Word(text: text, start: word.start)
        }
        var lines: [Line] = []
        var current: [Word] = []
        func flush(endingAt lineEnd: TimeInterval?) {
            guard !current.isEmpty else { return }
            guard current.contains(where: { $0.text.contains { $0.isLetter || $0.isNumber } }) else {
                current = []
                return
            }
            let start = current.first?.start ?? lines.last?.end ?? fallbackStart
            lines.append(Line(start: start, end: lineEnd ?? end, words: current))
            current = []
        }
        for (index, word) in words.enumerated() {
            current.append(word)
            let trimmed = word.text.trimmingCharacters(in: .whitespaces)
            let endsSentence = trimmed.last.map { ".?!…".contains($0) } ?? false
                || trimmed.hasSuffix(".”") || trimmed.hasSuffix("?”") || trimmed.hasSuffix("!”") || trimmed.hasSuffix(".\"")
            let longAtComma = current.count >= 18 && trimmed.hasSuffix(",")
            let veryLong = current.count >= 32
            if endsSentence || longAtComma || veryLong {
                let next = words.dropFirst(index + 1).first { $0.start != nil }?.start
                flush(endingAt: next)
            }
        }
        flush(endingAt: end)
        return lines
    }
}

/// The transcripts read so far, by file, kept in memory while the app runs
/// and in Caches across launches.
@MainActor
final class BookTranscriptStore {
    static let shared = BookTranscriptStore()

    private var transcripts: [String: BookTranscript] = [:]
    private var saveTasks: [String: Task<Void, Never>] = [:]

    private init() {}

    /// The key a file is kept under.
    static func key(for file: PlayableContentKey) -> String {
        "\(file.service).\(file.id)"
    }

    func transcript(for key: String) -> BookTranscript {
        if let transcript = transcripts[key] { return transcript }
        let loaded = (try? Data(contentsOf: Self.url(for: key)))
            .flatMap { try? JSONDecoder().decode(BookTranscript.self, from: $0) } ?? BookTranscript()
        transcripts[key] = loaded
        return loaded
    }

    func update(_ key: String, _ change: (inout BookTranscript) -> Void) -> BookTranscript {
        var transcript = transcript(for: key)
        change(&transcript)
        transcripts[key] = transcript
        scheduleSave(key)
        return transcript
    }

    private func scheduleSave(_ key: String) {
        saveTasks[key]?.cancel()
        saveTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let transcript = self?.transcripts[key],
                  let data = try? JSONEncoder().encode(transcript) else { return }
            let url = Self.url(for: key)
            Task.detached(priority: .utility) {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private static func url(for key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? String($0) : "_" }.joined()
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BookTranscripts", isDirectory: true)
            .appendingPathComponent(safe + ".json")
    }
}

/// A file's service and id, as the store keys it.
struct PlayableContentKey: Hashable, Sendable {
    let service: String
    let id: String
}
