import Foundation

/// Generic Open Graph meta-tag scraper. Used to pull title/description/image from
/// public web pages when official APIs aren't accessible (e.g. share extensions
/// without auth tokens).
public struct OpenGraphMeta: Sendable, Equatable {
    public let title: String?
    public let description: String?
    public let image: URL?

    public init(title: String? = nil, description: String? = nil, image: URL? = nil) {
        self.title = title
        self.description = description
        self.image = image
    }
}

public enum OpenGraphScraper {
    /// Fetches a URL with a browser User-Agent and extracts standard `og:*` meta tags.
    /// Pass `timeout` to override the per-request deadline (defaults to the session config).
    public static func fetch(url: URL, session: URLSession = .shared, timeout: TimeInterval? = nil) async -> OpenGraphMeta {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        if let timeout { request.timeoutInterval = timeout }
        guard let (data, _) = try? await session.data(for: request),
              let html = String(data: data, encoding: .utf8) else {
            return OpenGraphMeta()
        }
        return OpenGraphMeta(
            title: metaContent(property: "og:title", in: html),
            description: metaContent(property: "og:description", in: html),
            image: metaContent(property: "og:image", in: html).flatMap(URL.init(string:))
        )
    }

    static func metaContent(property: String, in html: String) -> String? {
        let patterns = [
            #"<meta\s+property=["']\#(property)["']\s+content=["']([^"']+)["']"#,
            #"<meta\s+content=["']([^"']+)["']\s+property=["']\#(property)["']"#,
            #"<meta\s+name=["']\#(property)["']\s+content=["']([^"']+)["']"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, range: range),
               match.numberOfRanges >= 2,
               let captureRange = Range(match.range(at: 1), in: html) {
                return decodeHTMLEntities(String(html[captureRange]))
            }
        }
        return nil
    }

    static func decodeHTMLEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
