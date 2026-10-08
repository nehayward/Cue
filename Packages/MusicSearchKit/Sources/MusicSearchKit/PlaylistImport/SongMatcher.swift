import Foundation

/// A song on the service being imported into, as the matcher sees it:
/// the fields every service's song carries, whatever else it has.
public struct SongCandidate: Sendable, Hashable {
    public let title: String
    /// The performers as the service writes them, in one line.
    public let artist: String?
    public let album: String?
    /// Seconds. Zero or less counts as unknown — Plex reports 0 for none.
    public let duration: TimeInterval?
    public let isrc: String?

    public init(title: String, artist: String?, album: String? = nil, duration: TimeInterval? = nil, isrc: String? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.isrc = isrc
    }
}

/// A song found for an imported track, and how sure the matcher is of it.
public struct SongMatch<Item: Sendable>: Sendable {
    public let item: Item
    /// 0…1. 1 is the same recording (the same ISRC) or the same title, artist
    /// and length.
    public let score: Double

    public var confidence: SongMatcher.Confidence {
        SongMatcher.Confidence(score: score)
    }

    public init(item: Item, score: Double) {
        self.item = item
        self.score = score
    }
}

/// Finds an imported song again on another service. Names are compared the
/// way a person would read them — case, accents, punctuation and "&"
/// against "and" don't count, nor do a title's decorations ("- Remastered
/// 2011", "(feat. Drake)") — but a different version does: a live take,
/// a remix or an instrumental only stands in for the studio song when
/// nothing closer exists, and then as something to check.
public enum SongMatcher {
    public enum Confidence: Int, Sendable, Comparable {
        /// Something close, but not the song as far as the matcher can tell:
        /// offered, never added on its own.
        case low
        /// Probably the song — another version, or the length differs.
        /// Added, and marked to check.
        case medium
        /// The song.
        case high

        init(score: Double) {
            switch score {
            case 0.9...: self = .high
            case 0.75...: self = .medium
            default: self = .low
            }
        }

        public static func < (lhs: Confidence, rhs: Confidence) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Below this, a candidate isn't offered at all.
    static let minimumScore = 0.5

    /// How alike `track` and `candidate` are, 0…1, or nil when they're
    /// plainly different songs.
    public static func score(_ track: ImportedTrack, _ candidate: SongCandidate) -> Double? {
        score(PreparedSong(track), PreparedSong(candidate))
    }

    /// `candidates` that could be `track`, best first.
    public static func rank<Item: Sendable>(
        _ track: ImportedTrack,
        among candidates: [Item],
        fields: (Item) -> SongCandidate
    ) -> [SongMatch<Item>] {
        let source = PreparedSong(track)
        return candidates
            .compactMap { item in
                score(source, PreparedSong(fields(item))).map { SongMatch(item: item, score: $0) }
            }
            .sorted { $0.score > $1.score }
    }

    /// What to type into a service's search to find `track`: the title
    /// without its decorations, any version that matters ("live"), and the
    /// lead artist. Decorations like "- 2011 Remaster" only narrow a search
    /// to the one service that wrote them that way.
    public static func searchTerm(for track: ImportedTrack, includingArtist: Bool = true) -> String {
        let parts = TitleParts(track.title)
        var words = [parts.core]
        words += parts.versions.sorted()
        if includingArtist, let lead = track.artists.first.map(ArtistNames.leadForSearch), !lead.isEmpty {
            words.append(lead)
        }
        return words.filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: - Scoring

    static func score(_ source: PreparedSong, _ candidate: PreparedSong) -> Double? {
        if let isrc = source.isrc, isrc == candidate.isrc {
            return 1
        }

        let title = titleScore(source, candidate)
        guard title >= 0.6 else { return nil }

        // A song with no artist to compare (a file without tags, a
        // compilation filed under Various Artists) is judged on the rest,
        // without credit for an artist nobody can see.
        let artist = artistScore(source, candidate) ?? 0.65
        guard artist >= 0.45 else { return nil }

        var score = (0.55 * title + 0.45 * artist)
        score *= durationFactor(source.duration, candidate.duration)
        score *= versionFactor(source.versions, candidate.versions)
        // The same song on another album (a compilation, a best-of) is
        // still the song, just not the first choice.
        if let album = source.album, let other = candidate.album, album != other {
            score *= 0.97
        }
        return score >= minimumScore ? score : nil
    }

    static func titleScore(_ a: PreparedSong, _ b: PreparedSong) -> Double {
        if a.coreTitle == b.coreTitle || a.fullTitle == b.fullTitle { return 1 }
        // One side keeps as a decoration what the other has in its title:
        // "Sweet Dreams (Are Made of This)" against "Sweet Dreams Are Made
        // of This".
        if a.coreTitle == b.fullTitle || a.fullTitle == b.coreTitle { return 0.95 }
        return max(dice(a.coreTitle, b.coreTitle), dice(a.fullTitle, b.fullTitle))
    }

    /// Nil when either side has no artist worth comparing.
    static func artistScore(_ a: PreparedSong, _ b: PreparedSong) -> Double? {
        guard let aLead = a.artistParts.first, let bLead = b.artistParts.first else { return nil }
        if a.artistLine == b.artistLine || aLead == bLead { return 1 }
        // The lead artist named among the other side's: "Queen" against
        // "Queen & David Bowie".
        if containsWords(b.artistLine, aLead) || containsWords(a.artistLine, bLead) { return 0.95 }
        if !Set(a.artistParts).isDisjoint(with: b.artistParts) { return 0.9 }
        var best = dice(a.artistLine, b.artistLine)
        for x in a.artistParts {
            for y in b.artistParts {
                best = max(best, dice(x, y))
            }
        }
        return best
    }

    /// Lengths a few seconds apart are the same recording; up to most of a
    /// minute is usually another edit of it (radio against album), worth
    /// adding and checking; beyond that it's another take altogether.
    static func durationFactor(_ a: TimeInterval?, _ b: TimeInterval?) -> Double {
        guard let a, let b, a > 0, b > 0 else { return 1 }
        switch abs(a - b) {
        case ...3: return 1
        case ...8: return 0.95
        case ...20: return 0.88
        case ...45: return 0.8
        default: return 0.6
        }
    }

    /// A different version costs a little; one that isn't the song as sung
    /// (an instrumental, karaoke) costs a lot.
    static func versionFactor(_ a: Set<String>, _ b: Set<String>) -> Double {
        let difference = a.symmetricDifference(b)
        if difference.isEmpty { return 1 }
        return difference.isDisjoint(with: TitleParts.heavyVersions) ? 0.8 : 0.6
    }

    /// Sørensen–Dice over character pairs: 1 for the same string, falling
    /// off with each letter added, dropped or changed.
    static func dice(_ a: String, _ b: String) -> Double {
        if a == b { return a.isEmpty ? 0 : 1 }
        let x = Array(a)
        let y = Array(b)
        guard x.count > 1, y.count > 1 else { return 0 }
        var pairs: [Pair: Int] = [:]
        for index in 0..<(x.count - 1) {
            pairs[Pair(x[index], x[index + 1]), default: 0] += 1
        }
        var shared = 0
        for index in 0..<(y.count - 1) {
            let pair = Pair(y[index], y[index + 1])
            if let count = pairs[pair], count > 0 {
                shared += 1
                pairs[pair] = count - 1
            }
        }
        return 2 * Double(shared) / Double(x.count - 1 + y.count - 1)
    }

    private struct Pair: Hashable {
        let first: Character
        let second: Character
        init(_ first: Character, _ second: Character) {
            self.first = first
            self.second = second
        }
    }

    /// Whether `phrase` appears in `text` as whole words.
    static func containsWords(_ text: String, _ phrase: String) -> Bool {
        guard !phrase.isEmpty, phrase.count <= text.count else { return false }
        return " \(text) ".contains(" \(phrase) ")
    }
}

// MARK: - Library index

/// A library's songs, normalized once and filed by title and artist, so each
/// imported track is compared with the few songs that could be it rather
/// than the whole library.
public struct SongIndex<Item: Sendable>: Sendable {
    private let items: [Item]
    private let songs: [PreparedSong]
    private let byTitle: [String: [Int]]
    private let byArtist: [String: [Int]]

    public init(_ items: [Item], fields: (Item) -> SongCandidate) {
        var songs: [PreparedSong] = []
        songs.reserveCapacity(items.count)
        var byTitle: [String: [Int]] = [:]
        var byArtist: [String: [Int]] = [:]
        for (index, item) in items.enumerated() {
            let song = PreparedSong(fields(item))
            songs.append(song)
            for key in Set([song.coreTitle, song.fullTitle]) where !key.isEmpty {
                byTitle[key, default: []].append(index)
            }
            for key in Set(song.artistParts) {
                byArtist[key, default: []].append(index)
            }
        }
        self.items = items
        self.songs = songs
        self.byTitle = byTitle
        self.byArtist = byArtist
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    /// The songs that could be `track`, best first, at most `limit`.
    public func matches(for track: ImportedTrack, limit: Int = 5) -> [SongMatch<Item>] {
        let source = PreparedSong(track)
        // Same title, or anything by the same artist — which finds a title
        // spelt differently ("Dont Stop" for "Don't Stop" is caught by
        // normalizing; "Pt. 2" for "Part 2" only by comparing).
        var indices = Set<Int>()
        for key in Set([source.coreTitle, source.fullTitle]) {
            indices.formUnion(byTitle[key] ?? [])
        }
        for key in source.artistParts {
            indices.formUnion(byArtist[key] ?? [])
        }
        return indices
            .compactMap { index in
                SongMatcher.score(source, songs[index]).map { SongMatch(item: items[index], score: $0) }
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Normalizing

/// A song's fields in the form they're compared in, worked out once.
struct PreparedSong: Sendable {
    let fullTitle: String
    let coreTitle: String
    let versions: Set<String>
    /// Every performer in one normalized line.
    let artistLine: String
    /// Each performer, normalized, lead first. Empty when there's nobody to
    /// compare.
    let artistParts: [String]
    let album: String?
    let duration: TimeInterval?
    let isrc: String?

    init(_ track: ImportedTrack) {
        self.init(
            title: track.title,
            artists: track.artists,
            album: track.album,
            duration: track.duration,
            isrc: track.isrc
        )
    }

    init(_ candidate: SongCandidate) {
        self.init(
            title: candidate.title,
            artists: candidate.artist.map { [$0] } ?? [],
            album: candidate.album,
            duration: candidate.duration,
            isrc: candidate.isrc
        )
    }

    private init(title: String, artists: [String], album: String?, duration: TimeInterval?, isrc: String?) {
        let parts = TitleParts(title)
        fullTitle = Normalizer.normalize(title)
        coreTitle = Normalizer.normalize(parts.core)
        versions = parts.versions

        let names = artists
            .flatMap(ArtistNames.split)
            .map(Normalizer.artist)
            .filter { !$0.isEmpty }
        if let lead = names.first, !ArtistNames.isPlaceholder(lead) {
            var seen = Set<String>()
            artistParts = names.filter { seen.insert($0).inserted }
            artistLine = Normalizer.artist(artists.joined(separator: " & "))
        } else {
            artistParts = []
            artistLine = ""
        }

        self.album = album.map { Normalizer.normalize(TitleParts($0).core) }.flatMap { $0.isEmpty ? nil : $0 }
        self.duration = duration
        let code = isrc?
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        self.isrc = code.flatMap { $0.count == 12 ? $0 : nil }
    }
}

/// A title split into the song's name and its decorations: what's in
/// brackets, after " - ", or after "feat.".
struct TitleParts {
    let core: String
    /// The versions the decorations name that make it a different take of
    /// the song — "live", "remix" — and none of those that don't (a
    /// remaster, a year, a featured artist).
    let versions: Set<String>

    /// Versions that aren't the song as people know it.
    static let heavyVersions: Set<String> = ["instrumental", "karaoke", "acapella"]

    /// Words in a decoration and the version they mean.
    private static let versionWords: [String: String] = [
        "live": "live",
        "unplugged": "live",
        "remix": "remix",
        "rmx": "remix",
        "acoustic": "acoustic",
        "instrumental": "instrumental",
        "karaoke": "karaoke",
        "demo": "demo",
        "acapella": "acapella",
        "cappella": "acapella",
        "reprise": "reprise",
        "extended": "extended",
        "slowed": "slowed",
        "sped": "sped up",
        "orchestral": "orchestral",
        "symphonic": "orchestral",
    ]

    init(_ title: String) {
        var core = ""
        var decorations: [String] = []
        var bracket = ""
        var depth = 0
        for character in title {
            switch character {
            case "(", "[", "{":
                if depth > 0 { bracket.append(character) }
                depth += 1
            case ")", "]", "}":
                if depth == 0 {
                    core.append(character)
                    continue
                }
                depth -= 1
                if depth == 0 {
                    decorations.append(bracket)
                    bracket = ""
                } else {
                    bracket.append(character)
                }
            default:
                if depth > 0 {
                    bracket.append(character)
                } else {
                    core.append(character)
                }
            }
        }
        if !bracket.isEmpty { decorations.append(bracket) }

        // Spotify's way: "Song - Remastered 2011", "Song - Live at Wembley".
        let dashes = [" - ", " – ", " — "].compactMap { core.range(of: $0) }
        if let dash = dashes.min(by: { $0.lowerBound < $1.lowerBound }),
           !core[..<dash.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty {
            decorations.append(String(core[dash.upperBound...]))
            core = String(core[..<dash.lowerBound])
        }

        if let featuring = Self.featuringRange(in: core) {
            decorations.append(String(core[featuring]))
            core = String(core[..<featuring.lowerBound])
        }

        core = core.trimmingCharacters(in: .whitespacesAndNewlines)
        // A title that's all decoration ("(Untitled)") is its own name.
        self.core = core.isEmpty ? title.trimmingCharacters(in: .whitespacesAndNewlines) : core

        var versions = Set<String>()
        for decoration in decorations {
            for word in Normalizer.normalize(decoration).split(separator: " ") {
                if let version = Self.versionWords[String(word)] {
                    versions.insert(version)
                }
            }
        }
        self.versions = versions
    }

    /// Where an unbracketed " feat. X" / " ft. X" / " featuring X" starts.
    private static func featuringRange(in title: String) -> Range<String.Index>? {
        let markers = [" feat. ", " feat ", " ft. ", " featuring "]
        let found = markers.compactMap { title.range(of: $0, options: .caseInsensitive) }
        guard let first = found.min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        return first.lowerBound..<title.endIndex
    }
}

enum ArtistNames {
    /// Ways a line of performers is joined, in the order they're tried.
    private static let separators = [
        ",", ";", "/", "、", "，",
        " & ", " + ", " x ", " × ", " vs. ", " vs ",
        " feat. ", " feat ", " ft. ", " ft ", " featuring ", " with ", " and ",
    ]

    /// One line of performers as each performer. Splits on "and" too, so
    /// "Simon and Garfunkel" comes apart; the whole line is still compared
    /// alongside, which keeps it together where it matters.
    static func split(_ line: String) -> [String] {
        var parts = [line]
        for separator in separators {
            parts = parts.flatMap { part in
                part.components(separatedBy: separator, caseInsensitive: true)
            }
        }
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The lead artist to search with: the line up to anyone featured. A
    /// comma or an "&" stays — it's as often a band's own ("Earth, Wind &
    /// Fire") as a list, and a search takes the extra names in its stride.
    static func leadForSearch(_ line: String) -> String {
        let markers = [";", " feat. ", " feat ", " ft. ", " featuring ", " with "]
        let cut = markers
            .compactMap { line.range(of: $0, options: .caseInsensitive)?.lowerBound }
            .min() ?? line.endIndex
        return line[..<cut].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Names a library files songs under when it doesn't know who made them.
    static func isPlaceholder(_ normalized: String) -> Bool {
        ["various artists", "various", "va", "unknown artist", "unknown", "artist", "no artist"].contains(normalized)
    }
}

enum Normalizer {
    /// Lowercase, without accents, apostrophes or punctuation, "&" read as
    /// "and", one space between words. Letters of every script stay.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var result = ""
        result.reserveCapacity(folded.count)
        var pendingSpace = false
        for character in folded {
            if character == "'" || character == "’" || character == "‘" || character == "`" {
                continue
            }
            if character.isLetter || character.isNumber {
                if pendingSpace, !result.isEmpty { result.append(" ") }
                pendingSpace = false
                result.append(character)
            } else if character == "&" || character == "+" {
                if !result.isEmpty { result.append(" ") }
                result.append("and")
                pendingSpace = true
            } else {
                pendingSpace = true
            }
        }
        return result
    }

    /// `normalize`, without a leading "the": "The Beatles" and "Beatles"
    /// are one band.
    static func artist(_ text: String) -> String {
        let normalized = normalize(text)
        if normalized.hasPrefix("the "), normalized.count > 4 {
            return String(normalized.dropFirst(4))
        }
        return normalized
    }
}

private extension String {
    func components(separatedBy separator: String, caseInsensitive: Bool) -> [String] {
        guard caseInsensitive else { return components(separatedBy: separator) }
        var parts: [String] = []
        var rest = self[...]
        while let range = rest.range(of: separator, options: .caseInsensitive) {
            parts.append(String(rest[..<range.lowerBound]))
            rest = rest[range.upperBound...]
        }
        parts.append(String(rest))
        return parts
    }
}
