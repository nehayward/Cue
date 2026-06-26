import Foundation

/// Resolves Deezer's native-app share links to a canonical web URL.
///
/// The Deezer *website* shares plain `https://www.deezer.com/<locale>/<type>/<id>`
/// links, which the path parser reads directly. The Deezer *app* instead shares
/// short "smart" links that carry no type/id in the path:
///   - `https://link.deezer.com/s/<token>`   (Branch.io)
///   - `https://deezer.page.link/<token>`     (Firebase Dynamic Links, legacy)
///   - `https://dzr.page.link/<token>`        (Firebase Dynamic Links, legacy)
///
/// This resolver follows such a link and recovers the underlying
/// `deezer.com/<type>/<id>` URL so the rest of the pipeline can treat it like a
/// website share.
public enum DeezerLinkResolver {
    /// Matches a canonical Deezer content URL, e.g.
    /// `https://www.deezer.com/us/track/123456` or `https://deezer.com/album/789`.
    private static let canonicalPattern =
        #"https?://(?:www\.)?deezer\.com/(?:[a-z]{2}/)?(?:track|album|playlist|artist)/\d+"#

    /// Whether `url` looks like an app-generated short link that needs resolving
    /// (as opposed to a canonical `deezer.com/<type>/<id>` URL the parser handles).
    public static func isShareLink(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "link.deezer.com"
            || host.hasSuffix("deezer.page.link")
            || host.hasSuffix("dzr.page.link")
    }

    /// Returns the canonical `deezer.com/<type>/<id>` URL a short link points to,
    /// or `nil` if it can't be resolved. Follows the HTTP redirect chain first,
    /// then falls back to scanning the returned HTML — Branch/Firebase serve an
    /// interstitial that embeds the destination in `og:url` or inline JSON.
    public static func resolve(_ url: URL, session: URLSession = .shared, timeout: TimeInterval? = nil) async -> URL? {
        var request = URLRequest(url: url)
        // A desktop User-Agent makes Branch/Firebase serve the web fallback URL
        // rather than an App Store redirect or app-only deep link.
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        if let timeout { request.timeoutInterval = timeout }

        guard let (data, response) = try? await session.data(for: request) else { return nil }

        // 1. The redirect chain may have already landed on the canonical page.
        if let finalURL = response.url, let match = firstCanonicalURL(in: finalURL.absoluteString) {
            return match
        }
        // 2. Otherwise dig the destination out of the HTML body.
        if let html = String(data: data, encoding: .utf8),
           let match = firstCanonicalURL(in: html) {
            return match
        }
        return nil
    }

    /// First canonical Deezer URL found in `text`. Handles JSON-escaped slashes
    /// (`https:\/\/www.deezer.com\/...`) that Branch/Firebase embed in scripts.
    private static func firstCanonicalURL(in text: String) -> URL? {
        let unescaped = text.replacingOccurrences(of: "\\/", with: "/")
        guard let regex = try? NSRegularExpression(pattern: canonicalPattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(unescaped.startIndex..., in: unescaped)
        guard let match = regex.firstMatch(in: unescaped, range: range),
              let matchRange = Range(match.range, in: unescaped) else { return nil }
        return URL(string: String(unescaped[matchRange]))
    }
}
