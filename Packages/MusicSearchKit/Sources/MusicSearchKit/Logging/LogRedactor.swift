import Foundation

/// Takes sign-in secrets out of a log line before it is written anywhere.
///
/// Log files leave the device as email attachments, and stream URLs carry
/// their credentials: Plex's `X-Plex-Token`, Subsonic's `t` (token), `s`
/// (salt) and `p` (password) query items. Lines that print a URL, a request
/// or a server response would hand those to whoever reads the email, so the
/// values are swapped for `<redacted>` and the rest of the line is kept.
///
/// It errs on the side of hiding: any `…token`, `…password`, `…secret` or
/// `…apikey` followed by `=` or `:` loses its value, so a debug line like
/// `playToken=3` reads `playToken=<redacted>`.
enum LogRedactor {
    static let placeholder = "<redacted>"

    /// Cheap substrings that every rule needs one of. Most lines have none,
    /// and skip the regular expressions altogether.
    private static let triggers = [
        "token", "password", "passwd", "secret", "key", "bearer",
        "?t=", "&t=", "?s=", "&s=", "?p=", "&p=", ";t=", ";s=", ";p="
    ]

    private static let rules: [(pattern: NSRegularExpression, template: String)] = [
        // Query items with short names that would be too broad on their own:
        // Subsonic's token, salt and password.
        (#"([?&;][tsp]=)[^&;\s"'<>#]+"#, "$1\(placeholder)"),
        // `Authorization: Bearer abc`.
        (#"(?i)(\bbearer\s+)[A-Za-z0-9._~+/=-]+"#, "$1\(placeholder)"),
        // `X-Plex-Token=abc` (query or header), `token: abc`,
        // `accessToken="abc"` (Plex XML), `"authToken":"abc"` (JSON),
        // `api_key=abc`.
        (#"(?i)(\b[\w-]*(?:token|password|passwd|secret|api_?key)\b"?\s*[:=]\s*"?)[^\s"',;&<>]+"#, "$1\(placeholder)"),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    static func redact(_ text: String) -> String {
        guard triggers.contains(where: { text.range(of: $0, options: .caseInsensitive) != nil }) else {
            return text
        }
        var result = text
        for rule in rules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.pattern.stringByReplacingMatches(in: result, range: range, withTemplate: rule.template)
        }
        return result
    }
}
