import Foundation

/// Auth-free Apple Music metadata via `og:*` meta tags scraped from `music.apple.com`.
/// Useful from share extensions where the iTunes Search API doesn't cover the
/// content (curated/editorial playlists with `pl.u-...` IDs, some albums).
public struct AppleMusicOpenGraph: Sendable, Equatable {
    public let title: String?
    public let description: String?
    public let image: URL?

    /// Apple Music's `og:title` for songs is sometimes `"Track. Album, with commas."`.
    /// Strip the album portion so the displayed title isn't a run-on.
    /// Conservative: only splits when the first segment is >= 5 chars (skips
    /// abbreviations like `Mr.`/`Dr.`/`St.`) and the second segment exists.
    public var resolvedTitle: String? {
        guard var title = title?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if title.hasSuffix(".") { title.removeLast() }
        if let range = title.range(of: ". ") {
            let first = title[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let rest = title[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if first.count >= 5, !rest.isEmpty {
                return first
            }
        }
        return title
    }

    /// Best-effort artist/curator extracted from page metadata.
    /// Apple Music's `og:description` formats vary by content type:
    ///   Track:    "Listen to <Track> by <Artist> on Apple Music."
    ///   Album:    "Album · YEAR · NN Songs"  (artist not reliably present)
    ///   Playlist: "Playlist · <Curator> · NN Songs"
    /// We try a few patterns; nil means we couldn't find it confidently.
    public var resolvedAuthor: String? {
        guard let description else { return nil }

        // Pattern 1: "Listen to ... by <Artist> on Apple Music."
        if let range = description.range(of: #"by\s+(.+?)\s+on\s+Apple Music"#, options: .regularExpression) {
            let captured = description[range]
                .replacingOccurrences(of: #"^by\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+on\s+Apple Music.*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !captured.isEmpty { return captured }
        }

        // Pattern 2: "<Type> · <Author> · <Year>" — author is segment index 1.
        let parts = description
            .components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if parts.count >= 2, !parts[1].isEmpty { return parts[1] }

        return nil
    }
}

public enum AppleMusicOpenGraphAPI {
    public static func lookup(url: URL, session: URLSession = .shared, timeout: TimeInterval? = nil) async -> AppleMusicOpenGraph {
        let og = await OpenGraphScraper.fetch(url: url, session: session, timeout: timeout)
        return AppleMusicOpenGraph(title: og.title, description: og.description, image: og.image)
    }
}
