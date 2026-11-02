import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A book's chapters as Audible has them, from Audnexus
/// (`api.audnex.us/books/<asin>/chapters`), which an Audiobookshelf server
/// also answers for (`/api/search/chapters`, its chapter editor's Lookup).
/// The last place a book's chapters come from: for a file with no marks of
/// its own, whose server found none either.
///
/// Audible's times are for Audible's edition, which opens and closes with
/// its branding ("This is Audible"); a rip may have kept it or cut it. So
/// the chapters are laid on the book only when its length matches one or
/// the other (`chapters(fitting:)`), never stretched to fit.
public struct AudnexusChapters: Decodable, Sendable {
    public let brandIntroDurationMs: Double?
    public let brandOutroDurationMs: Double?
    public let runtimeLengthMs: Double?
    public let chapters: [Chapter]?
    /// Audiobookshelf's answer for a book Audible has no chapters for:
    /// "Chapters not found", or an ASIN it took for invalid.
    public let error: String?

    public struct Chapter: Decodable, Sendable {
        public let lengthMs: Double
        public let startOffsetMs: Double
        public let title: String?
    }

    /// An answer of none, for a book Audnexus doesn't know.
    public static let none = AudnexusChapters(brandIntroDurationMs: nil, brandOutroDurationMs: nil, runtimeLengthMs: nil, chapters: nil, error: "Chapters not found")

    /// The chapters on a book `duration` seconds long: as Audible has them
    /// when the book's length is Audible's, or without the branding (each
    /// start brought forward by the intro, an outro-length last chapter
    /// dropped, as Audiobookshelf's Remove Audible Branding does) when it's
    /// that length instead. Nil when it's neither, give or take
    /// `tolerance(for:)`: another edition, whose chapters would land in
    /// the wrong places.
    public func chapters(fitting duration: TimeInterval) -> [AudiobookChapter]? {
        guard let marks = chapters, !marks.isEmpty, let runtimeLengthMs, duration > 0 else { return nil }
        let intro = (brandIntroDurationMs ?? 0) / 1000
        let outro = (brandOutroDurationMs ?? 0) / 1000
        let runtime = runtimeLengthMs / 1000
        let branded = abs(runtime - duration)
        let unbranded = abs(runtime - intro - outro - duration)
        guard Swift.min(branded, unbranded) <= Self.tolerance(for: duration) else { return nil }
        let removesBranding = (intro > 0 || outro > 0) && unbranded < branded

        var starts: [(title: String?, start: TimeInterval)] = []
        for (index, mark) in marks.enumerated() {
            var start = mark.startOffsetMs / 1000
            if removesBranding {
                if index == marks.count - 1, index > 0, mark.lengthMs / 1000 <= outro { continue }
                start = start < intro ? 0 : start - intro
            }
            guard start < duration else { continue }
            starts.append((mark.title, start))
        }
        return starts.enumerated().map { index, mark in
            let end = index + 1 < starts.count ? starts[index + 1].start : duration
            let title = mark.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Chapter \(index + 1)"
            return AudiobookChapter(id: index, title: title, start: mark.start, end: end)
        }
    }

    /// How far the book's length may be from Audible's: a minute and a
    /// half, or a fifth of a percent of a long book.
    static func tolerance(for duration: TimeInterval) -> TimeInterval {
        Swift.max(90, duration * 0.002)
    }

    /// Whether `asin` is an Audible id: ten letters and digits.
    public static func isASIN(_ asin: String) -> Bool {
        asin.count == 10 && asin.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
    }

    /// The ASIN in a Plex book's guid, for a book matched by the Audnexus
    /// agent (`com.plexapp.agents.audnexus://B002V0QK4C?lang=en`), with the
    /// region when the id carries one (`…://B002V0QK4C_uk`).
    public static func asin(fromPlexGuid guid: String?) -> (asin: String, region: String?)? {
        guard let guid, let range = guid.range(of: "audnexus://") else { return nil }
        let id = guid[range.upperBound...].prefix { $0 != "?" && $0 != "/" }
        let parts = id.split(separator: "_", maxSplits: 1).map(String.init)
        guard let asin = parts.first?.uppercased(), isASIN(asin) else { return nil }
        return (asin, parts.count > 1 ? parts[1].lowercased() : nil)
    }

    /// Audnexus's own address for a book's chapters.
    public static func url(asin: String, region: String = "us") -> URL? {
        var components = URLComponents(string: "https://api.audnex.us/books/\(asin)/chapters")
        components?.queryItems = [URLQueryItem(name: "region", value: region)]
        return components?.url
    }
}

/// Asks Audnexus for a book's chapters straight, for a Plex book (an
/// Audiobookshelf server asks it on Cue's behalf).
public enum AudnexusAPI {
    /// Audible's chapters for `asin`: `.none` for a book it doesn't know,
    /// nil when it couldn't be asked.
    public static func chapters(asin: String, region: String = "us") async -> AudnexusChapters? {
        guard AudnexusChapters.isASIN(asin), let url = AudnexusChapters.url(asin: asin, region: region) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        switch http.statusCode {
        case 200:
            return try? JSONDecoder().decode(AudnexusChapters.self, from: data)
        case 404:
            return AudnexusChapters.none
        default:
            return nil
        }
    }
}
