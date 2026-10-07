import Foundation

/// LRCLIB (lrclib.net): free, keyless, crowd-sourced lyrics, timed for most
/// songs. Asked for a song by its title, artist, album and length when its
/// own service has no timed lyrics.
///
/// A song LRCLIB doesn't know is `nil`; a request that didn't get an answer
/// throws, so a passing fault isn't remembered as "no lyrics".
public enum LRCLibAPI {
    static let base = URL(string: "https://lrclib.net/api")!

    /// LRCLIB asks clients to name themselves.
    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Cue/\(version) (https://cue.dance)"
    }()

    /// Seconds apart a song's length and a record's can be and still be the
    /// same recording. LRCLIB's own match allows two.
    static let durationTolerance: TimeInterval = 3

    struct Record: Decodable, Equatable {
        let id: Int
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    struct BadResponse: Error {
        let statusCode: Int
    }

    /// A record LRCLIB matched a song to, how, and its lyrics.
    public struct Match: Sendable {
        public let id: Int
        public let trackName: String?
        public let artistName: String?
        public let albumName: String?
        /// Seconds.
        public let duration: Double?
        /// "exact" (the full artist), "exact, first artist" or "search".
        public let via: String
        public let lyrics: Lyrics
    }

    /// The song's lyrics, timed when LRCLIB has them so.
    ///
    /// Tries an exact match first — the full artist, then the first artist
    /// of a credit like "A feat. B", since LRCLIB files most songs under
    /// one — and then a search, keeping only records within a few seconds
    /// of the song's length so a live take or a remix isn't shown against
    /// the studio cut.
    public static func lyrics(
        title: String,
        artist: String,
        album: String?,
        duration: TimeInterval?,
        session: URLSession = .shared
    ) async throws -> Lyrics? {
        try await match(title: title, artist: artist, album: album, duration: duration, session: session)?.lyrics
    }

    /// `lyrics(title:artist:album:duration:)` with the record it came from.
    public static func match(
        title: String,
        artist: String,
        album: String?,
        duration: TimeInterval?,
        session: URLSession = .shared
    ) async throws -> Match? {
        // A take whose title says it has no singing: LRCLIB, written by
        // anyone, often files the song's words under it too.
        guard !isInstrumentalTitle(title) else { return nil }
        let duration = duration.flatMap { $0 > 0 ? $0 : nil }
        if let duration {
            var artists = [artist]
            let primary = primaryArtist(artist)
            if primary != artist { artists.append(primary) }
            for (index, name) in artists.enumerated() {
                if let record = try await exact(title: title, artist: name, album: album, duration: duration, session: session),
                   let lyrics = lyrics(from: record) {
                    return Match(record, via: index == 0 ? "exact" : "exact, first artist", lyrics: lyrics)
                }
            }
        }
        let records = try await search(title: searchTitle(title), artist: primaryArtist(artist), session: session)
        guard let record = best(of: records, title: title, duration: duration), let lyrics = lyrics(from: record) else { return nil }
        return Match(record, via: "search", lyrics: lyrics)
    }

    // MARK: - Requests

    private static func exact(title: String, artist: String, album: String?, duration: TimeInterval, session: URLSession) async throws -> Record? {
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "duration", value: "\(Int(duration.rounded()))")
        ]
        if let album, !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        let (data, status) = try await get("get", items, session: session)
        // A miss is a 404, or now and then a 503 while LRCLIB asks
        // elsewhere and gives up; either way the search is next.
        guard status == 200 else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private static func search(title: String, artist: String, session: URLSession) async throws -> [Record] {
        let (data, status) = try await get("search", [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ], retryingServerErrors: true, session: session)
        guard status == 200 else { throw BadResponse(statusCode: status) }
        return (try? JSONDecoder().decode([Record].self, from: data)) ?? []
    }

    /// One retry, a second later, for a request that timed out — and, for
    /// a search, one LRCLIB answered with a server error: a check of 150
    /// songs saw one in ten do either, nearly all passing. (An exact
    /// match's 503 is LRCLIB giving up on the song, so it isn't retried.)
    private static func get(_ endpoint: String, _ items: [URLQueryItem], retryingServerErrors: Bool = false, session: URLSession) async throws -> (Data, Int) {
        var components = URLComponents(url: base.appending(path: endpoint), resolvingAgainstBaseURL: false)!
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for attempt in 0..<2 {
            let isLast = attempt == 1
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if retryingServerErrors, status >= 500, !isLast {
                    try await Task.sleep(for: .seconds(1))
                    continue
                }
                return (data, status)
            } catch let error as URLError where error.code == .timedOut && !isLast {
                try await Task.sleep(for: .seconds(1))
            }
        }
        throw URLError(.timedOut)
    }

    // MARK: - Matching

    /// The search result to use: within the length tolerance when the
    /// length is known, the same title before a near one, timed before
    /// plain, and the closest length after that.
    static func best(of records: [Record], title: String, duration: TimeInterval?) -> Record? {
        let wanted = normalized(searchTitle(title))
        let candidates = records.filter { record in
            guard record.syncedLyrics != nil || record.plainLyrics != nil || record.instrumental == true else { return false }
            guard let duration else { return true }
            guard let length = record.duration else { return false }
            return abs(length - duration) <= durationTolerance
        }
        return candidates.min { lhs, rhs in
            let lhsTitle = normalized(searchTitle(lhs.trackName ?? "")) == wanted
            let rhsTitle = normalized(searchTitle(rhs.trackName ?? "")) == wanted
            if lhsTitle != rhsTitle { return lhsTitle }
            let lhsTimed = lhs.syncedLyrics?.isEmpty == false
            let rhsTimed = rhs.syncedLyrics?.isEmpty == false
            if lhsTimed != rhsTimed { return lhsTimed }
            guard let duration else { return false }
            return abs((lhs.duration ?? 0) - duration) < abs((rhs.duration ?? 0) - duration)
        }
    }

    static func lyrics(from record: Record) -> Lyrics? {
        if let synced = record.syncedLyrics, let lyrics = Lyrics.parse(synced, source: .lrclib), lyrics.isSynced {
            return lyrics
        }
        if let plain = record.plainLyrics, let lyrics = Lyrics.parse(plain, source: .lrclib) {
            return lyrics
        }
        return record.instrumental == true ? .instrumental(source: .lrclib) : nil
    }

    /// The title without what streaming services add to it and LRCLIB's
    /// records mostly don't carry: a featured artist, a remaster year.
    public static func searchTitle(_ title: String) -> String {
        var result = title
        // "(feat. X)", "[with X]"
        result = result.replacing(#/\s*[\(\[](?:feat\.?|ft\.?|featuring|with)\s[^\)\]]*[\)\]]/#.ignoresCase(), with: "")
        // "(Remastered 2011)", "[2009 Remaster]"
        result = result.replacing(#/\s*[\(\[][^\)\]]*remaster[^\)\]]*[\)\]]/#.ignoresCase(), with: "")
        // " - 2011 Remaster", " - Remastered Version"
        result = result.replacing(#/\s+-\s+[^-]*remaster[^-]*$/#.ignoresCase(), with: "")
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? title : trimmed
    }

    /// A title that names a take without singing: "(Instrumental)",
    /// "(strings only)", "[Karaoke Version]", "- Backing Track".
    public static func isInstrumentalTitle(_ title: String) -> Bool {
        title.firstMatch(of: #/[\(\[\-–—]\s*[^\)\]]*\b(instrumental|karaoke|backing track|strings only|orchestral version|no vocals?)\b/#.ignoresCase()) != nil
    }

    /// The first name in a credit: "A feat. B", "A & B", "A, B" are A's.
    /// Only for asking a second time — "Simon & Garfunkel" is one artist,
    /// so the full credit is always tried first.
    static func primaryArtist(_ artist: String) -> String {
        let separators = #/\s+(?:feat\.?|ft\.?|featuring|with|&|and|x|\+)\s+|\s*[,;/]\s*/#.ignoresCase()
        guard let match = artist.firstMatch(of: separators) else { return artist }
        let first = artist[..<match.range.lowerBound].trimmingCharacters(in: .whitespaces)
        return first.isEmpty ? artist : first
    }

    private static func normalized(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }
}

extension LRCLibAPI.Match {
    init(_ record: LRCLibAPI.Record, via: String, lyrics: Lyrics) {
        self.init(id: record.id, trackName: record.trackName, artistName: record.artistName, albumName: record.albumName, duration: record.duration, via: via, lyrics: lyrics)
    }
}
