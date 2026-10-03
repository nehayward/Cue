import Foundation

/// Takes sign-in secrets out of a log line before it is written anywhere.
///
/// Log files leave the device as bug-report attachments, and URLs often carry
/// credentials: Plex's `X-Plex-Token`, the Subsonic API's `t` (token), `s`
/// (salt) and `p` (password) query items. Lines that print a URL, a request
/// or a server response would hand those to whoever reads the report, so the
/// values are swapped for `<redacted>` and the rest of the line is kept.
///
/// It errs on the side of hiding: any `…token`, `…password`, `…secret` or
/// `…apikey` followed by `=` or `:` loses its value, so a debug line like
/// `playToken=3` reads `playToken=<redacted>`.
enum Redactor {
    static let placeholder = "<redacted>"

    private static let rules: [(pattern: NSRegularExpression, template: String)] = [
        // Query items with short names that would be too broad on their own:
        // the Subsonic API's token, salt and password.
        (#"([?&;][tsp]=)[^&;\s"'<>#]+"#, "$1\(placeholder)"),
        // `Authorization: Bearer abc`.
        (#"(?i)(\bbearer\s+)[A-Za-z0-9._~+/=-]+"#, "$1\(placeholder)"),
        // `X-Plex-Token=abc` (query or header), `token: abc`,
        // `accessToken="abc"` (Plex XML), `"authToken":"abc"` (JSON),
        // `api_key=abc`.
        (#"(?i)(\b[\w-]*(?:token|password|passwd|secret|api_?key)\b"?\s*[:=]\s*"?)[^\s"',;&<>]+"#, "$1\(placeholder)"),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    static func redact(_ text: String) -> String {
        guard mightContainSecret(text) else { return text }
        var result = text
        for rule in rules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.pattern.stringByReplacingMatches(in: result, range: range, withTemplate: rule.template)
        }
        return result
    }

    /// Whether any rule could match: one pass over the bytes looking for
    /// what each needs (`?t=`, `bearer`, `token`, `passw`, `secret`,
    /// `apikey`, `api_key`). This runs on the thread that logs, often the
    /// main one, so it has to be cheap. Most lines have none of them and
    /// never reach the regular expressions, which cost tens of microseconds.
    static func mightContainSecret(_ text: String) -> Bool {
        var text = text
        return text.withUTF8 { bytes in
            for index in bytes.indices {
                switch lowercased(bytes[index]) {
                case UInt8(ascii: "?"), UInt8(ascii: "&"), UInt8(ascii: ";"):
                    if index + 2 < bytes.count, bytes[index + 2] == UInt8(ascii: "=") {
                        switch bytes[index + 1] {
                        case UInt8(ascii: "t"), UInt8(ascii: "s"), UInt8(ascii: "p"): return true
                        default: break
                        }
                    }
                case UInt8(ascii: "t"):
                    if matches("token", in: bytes, at: index) { return true }
                case UInt8(ascii: "p"):
                    if matches("passw", in: bytes, at: index) { return true }
                case UInt8(ascii: "s"):
                    if matches("secret", in: bytes, at: index) { return true }
                case UInt8(ascii: "b"):
                    if matches("bearer", in: bytes, at: index) { return true }
                case UInt8(ascii: "a"):
                    if matches("apikey", in: bytes, at: index) || matches("api_key", in: bytes, at: index) { return true }
                default:
                    break
                }
            }
            return false
        }
    }

    /// Whether `word` (lowercase ASCII) starts at `start`, ignoring case.
    private static func matches(_ word: StaticString, in bytes: UnsafeBufferPointer<UInt8>, at start: Int) -> Bool {
        let count = word.utf8CodeUnitCount
        guard start + count <= bytes.count else { return false }
        let word = word.utf8Start
        for offset in 0..<count where lowercased(bytes[start + offset]) != word[offset] {
            return false
        }
        return true
    }

    private static func lowercased(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte | 0x20 : byte
    }
}
