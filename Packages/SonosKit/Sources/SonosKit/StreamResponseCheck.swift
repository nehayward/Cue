import Foundation

/// Whether a finished fetch of a song is a song. A server that refuses a
/// request — Plex turning down a transcode it has no target for, a stale
/// token — answers with a short HTML or XML page and a 4xx, and a download
/// task hands that over as a "finished" file just the same. Saved as
/// `.opus`, it sits in Downloads as an 89-byte song that never plays.
public enum StreamResponseCheck {
    public struct Refused: LocalizedError, Sendable {
        public let statusCode: Int?
        public let mimeType: String?

        public var errorDescription: String? {
            let status = statusCode.map { " (HTTP \($0))" } ?? ""
            if let statusCode, (400..<500).contains(statusCode) {
                return "The server refused the request\(status). If Streaming Quality is on, try another format or Original under Settings ▸ Services"
            }
            if let statusCode, statusCode >= 500 {
                return "The server couldn't serve the song\(status)"
            }
            return "The server sent a page instead of a song\(mimeType.map { " (\($0))" } ?? "")"
        }
    }

    /// The error for a response that isn't audio, or nil when it may be.
    /// A missing response (a non-HTTP URL, a file) passes.
    public static func refusal(in response: URLResponse?) -> Refused? {
        guard let http = response as? HTTPURLResponse else { return nil }
        let mime = http.mimeType?.lowercased()
        if !(200..<300).contains(http.statusCode) {
            return Refused(statusCode: http.statusCode, mimeType: mime)
        }
        if let mime, mime.hasPrefix("text/") || mime.hasSuffix("/xml") || mime.hasSuffix("/json") || mime.hasSuffix("+xml") {
            return Refused(statusCode: http.statusCode, mimeType: mime)
        }
        return nil
    }
}
