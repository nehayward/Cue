import Foundation

/// A book's description as text to read. Audiobookshelf keeps descriptions
/// as HTML, and Plex's book agents fill the summary with the same
/// (`<br /><br />` between paragraphs), which a `Text` shows as it is.
public enum AudiobookText {
    /// `html` as plain text: line breaks and paragraph ends become new
    /// lines, list items bullets, other tags go, and entities are decoded.
    /// Text with no tags comes back as it was, trimmed.
    public static func plain(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"</(p|div|h[1-6]|ul|ol)>"#, with: "\n\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<li[^>]*>"#, with: "• ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"</li>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        text = decodingEntities(text)
        text = text.replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Named entities a description uses, and numeric ones, in one pass,
    /// so `&amp;lt;` reads `&lt;` rather than `<`.
    static func decodingEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = Substring(text)
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let tail = rest[ampersand...]
            if let semicolon = tail.prefix(12).firstIndex(of: ";"),
               let decoded = entity(String(tail[tail.index(after: ampersand)..<semicolon])) {
                result += decoded
                rest = tail[tail.index(after: semicolon)...]
            } else {
                result += "&"
                rest = tail.dropFirst()
            }
        }
        return result + rest
    }

    private static func entity(_ name: String) -> String? {
        if name.hasPrefix("#") {
            let number = name.dropFirst()
            let value = number.first == "x" || number.first == "X"
                ? UInt32(number.dropFirst(), radix: 16)
                : UInt32(number)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return named[name]
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "rsquo": "\u{2019}", "lsquo": "\u{2018}", "rdquo": "\u{201D}", "ldquo": "\u{201C}",
        "mdash": "\u{2014}", "ndash": "\u{2013}", "hellip": "\u{2026}", "eacute": "é"
    ]
}
