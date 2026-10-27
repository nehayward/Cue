import Foundation

/// A dictionary entry laid out from the plain text the Mac's dictionary
/// gives (`MacBridgeable.definition(of:)`): the headword and how it's said,
/// then its parts of speech, numbered senses, the senses under those, and
/// its sections (PHRASES, ORIGIN). The text carries none of the page's
/// styling, so the parts are found by how the New Oxford American
/// Dictionary writes them; whatever doesn't fit reads as plain text.
struct DictionaryEntry: Equatable {
    enum Part: Equatable {
        /// "noun", "verb" and what follows on its line: a grammar note
        /// ("[with object]"), or the definition of a word with one sense.
        case partOfSpeech(String, String)
        /// A numbered sense: its number, and its definition.
        case sense(String, String)
        /// A sense under the one before it ("•").
        case subsense(String)
        /// PHRASES, DERIVATIVES, ORIGIN and the like, and what's in it.
        case section(String, String)
        case text(String)
    }

    /// The word as the dictionary heads it ("ap·ple"); nil when the text
    /// isn't laid out as an entry.
    let headword: String?
    let pronunciation: String?
    let parts: [Part]

    private static let partsOfSpeech = [
        "plural noun", "noun", "verb", "adjective", "adverb", "pronoun", "preposition", "conjunction",
        "exclamation", "determiner", "abbreviation", "prefix", "suffix", "combining form", "contraction", "symbol",
    ]
    private static let sections = ["PHRASAL VERBS", "PHRASES", "DERIVATIVES", "ORIGIN", "USAGE", "NOTE"]

    /// Where each part starts, as a line break put before it.
    private static let breaks: [(NSRegularExpression, String)] = {
        let partsOfSpeech = DictionaryEntry.partsOfSpeech.joined(separator: "|")
        let sections = DictionaryEntry.sections.joined(separator: "|")
        let patterns = [
            // A part of speech opening the entry or following a sentence.
            ("(^|(?<=[.!?)\\]’”] ))(\(partsOfSpeech))(?= |$)", "\n$2"),
            // A sense's number, before its definition or a grammar note.
            (" (\\d{1,2}) (?=[a-z\\[(‘“'\"•])", "\n$1 "),
            (" • ", "\n• "),
            (" (\(sections))(?= )", "\n$1"),
        ]
        return patterns.compactMap { pattern, template in
            (try? NSRegularExpression(pattern: pattern)).map { ($0, template) }
        }
    }()

    init(_ text: String) {
        // "ap·ple | ˈapəl | noun 1 the round fruit…"; past the first two
        // bars, they part a sense's examples.
        let pieces = text.components(separatedBy: " | ")
        var body = text
        if pieces.count >= 3, pieces[1].count < 60 {
            headword = pieces[0].trimmingCharacters(in: .whitespaces)
            pronunciation = pieces[1].trimmingCharacters(in: .whitespaces)
            body = pieces.dropFirst(2).joined(separator: " | ")
        } else if pieces.count == 2 {
            headword = pieces[0].trimmingCharacters(in: .whitespaces)
            pronunciation = nil
            body = pieces[1]
        } else {
            headword = nil
            pronunciation = nil
        }
        for (expression, template) in Self.breaks {
            body = expression.stringByReplacingMatches(in: body, range: NSRange(body.startIndex..., in: body), withTemplate: template)
        }
        parts = body.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map(Self.part)
    }

    private static func part(_ line: String) -> Part {
        if let title = sections.first(where: { line.hasPrefix($0 + " ") }) {
            return .section(title, String(line.dropFirst(title.count + 1)))
        }
        if line.hasPrefix("• ") {
            return .subsense(String(line.dropFirst(2)))
        }
        let number = line.prefix { $0.isNumber }
        if !number.isEmpty, number.count <= 2, line.dropFirst(number.count).first == " " {
            return .sense(String(number), String(line.dropFirst(number.count + 1)))
        }
        if let label = partsOfSpeech.first(where: { line == $0 || line.hasPrefix($0 + " ") }) {
            return .partOfSpeech(label, String(line.dropFirst(label.count)).trimmingCharacters(in: .whitespaces))
        }
        return .text(line)
    }
}
