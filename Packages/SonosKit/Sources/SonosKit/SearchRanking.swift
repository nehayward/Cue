import Foundation

/// Scores and orders search results so ranking feels like a first-party music
/// app (Spotify / Apple Music): exact and prefix title matches first, then
/// whole-word matches, with popularity breaking ties between comparable
/// matches and artists nudged above same-named tracks/albums.
///
/// Scoring is service-agnostic and produces scores comparable across services,
/// so a future multiservice (merged) search can rank one combined list.
enum SearchRanking {

    /// Deduplicates exact repeats (same ID) and sorts content by relevance
    /// score (descending). Ties keep the incoming order: services already
    /// return relevance-ordered results, so equal-scoring items shouldn't be
    /// scrambled alphabetically.
    ///
    /// Deliberately no fuzzy cross-source dedup: the "same" song from two
    /// services, the library and the catalog, or two Plex sections stays
    /// visible so the user chooses which copy to play — and downstream
    /// filters (like Plex's per-section filter) never lose the copy they
    /// needed.
    static func sort(
        _ playableContent: [PlayableContent],
        query: String,
        recentlyPlayedIDs: Set<String> = [],
        now: Date = Date()
    ) -> [PlayableContent] {
        var uniqueItems: [String: (item: PlayableContent, score: Double, index: Int)] = [:]

        for (index, item) in playableContent.enumerated() {
            let itemScore = score(item: item, query: query, recentlyPlayedIDs: recentlyPlayedIDs, now: now)
            let key = "\(item.id)-\(item.title)-\(item.subtitle)"
            if let existing = uniqueItems[key] {
                if itemScore > existing.score {
                    uniqueItems[key] = (item, itemScore, existing.index)
                }
            } else {
                uniqueItems[key] = (item, itemScore, index)
            }
        }

        var entries = Array(uniqueItems.values)

        // Spotify-style top result: exactly one artist — the best-scoring,
        // genuinely matching one — gets the top-slot boost. Boosting every
        // matching artist walls off tracks and albums behind a run of
        // same-named artists (searching "dua" must rank Dua Lipa and her
        // popular songs above ten obscure artists named "Dua").
        let topArtist = entries.indices
            .filter { entries[$0].item.content.type == .artist }
            .max { lhs, rhs in
                if entries[lhs].score != entries[rhs].score { return entries[lhs].score < entries[rhs].score }
                return entries[lhs].index > entries[rhs].index
            }
        if let topArtist {
            let text = textScore(item: entries[topArtist].item, query: query)
            if text >= topArtistMinimumText {
                // Scale the bonus by the artist's own popularity (half
                // strength when unknown): a song-title query must not crown
                // a nobody who happens to share the name — "just dance"
                // means the Lady Gaga song, not an obscure artist named
                // "Just Dance". A genuinely popular artist still tops their
                // own hit tracks.
                let artistQuality = min(Double(entries[topArtist].item.metadata?.popularity ?? 0) / 100, 1)
                entries[topArtist].score += topArtistBonus * text * (0.5 + 0.5 * artistQuality)

                // Spotify's search API reports popularity for tracks and
                // artists but not albums, which buried the focused artist's
                // albums below every popular track. Albums by the top artist
                // inherit its popularity as their quality signal so they
                // surface alongside the artist's tracks.
                let artistName = normalized(entries[topArtist].item.title)
                if !artistName.isEmpty, artistQuality > 0 {
                    for index in entries.indices {
                        let candidate = entries[index].item
                        guard candidate.content.type == .album || candidate.content.type == .libraryAlbum,
                              (candidate.metadata?.popularity ?? 0) == 0,
                              matchesWholeWords(normalized(candidate.metadata?.artist ?? candidate.subtitle), phrase: artistName)
                        else { continue }
                        entries[index].score += artistQuality * popularityWeight
                    }
                }
            }
        }

        return entries
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.index < rhs.index
            }
            .map { $0.item }
    }

    // MARK: - Weights

    /// Text relevance dominates so a weak title match can never ride
    /// popularity to the top.
    private static let textWeight = 0.7
    /// Popularity orders results whose text matches are comparable, and is
    /// weighted heavily enough that a popular artist's hits outrank obscure
    /// exact-name matches — mirroring Spotify/Apple ordering. Spotify and
    /// Tidal report it; other services leave it nil.
    private static let popularityWeight = 0.25
    /// A match on the subtitle (artist/album line) is meaningful but weaker
    /// than a match on the item's own title.
    private static let subtitleFactor = 0.9
    /// Extra lift for the single best-matching artist (applied in `sort`),
    /// so the artist the user is likely typing lands on top.
    private static let topArtistBonus = 0.2
    /// An artist must actually match this well before it can take the top slot.
    private static let topArtistMinimumText = 0.75
    /// Matches that need title + subtitle combined ("rhapsody queen").
    private static let combinedFactor = 0.9
    /// Matching the title with its version suffix stripped ("Love Story
    /// (Taylor's Version)" for the query "love story") is nearly as good as
    /// matching the full title.
    private static let primaryTitleFactor = 0.97
    /// Items the user has actually played rise above comparable matches.
    private static let historyWeight = 0.1
    /// Releases from the last two years get a slight lift — strongest when
    /// brand new — like Spotify's search.
    private static let recencyWeight = 0.05
    private static let recencyWindow: TimeInterval = 2 * 365.25 * 24 * 60 * 60

    static func score(
        item: PlayableContent,
        query: String,
        recentlyPlayedIDs: Set<String> = [],
        now: Date = Date()
    ) -> Double {
        let text = textScore(item: item, query: query)

        // Spotify reports popularity (0-100); Plex and the local library
        // report user star ratings (0-10) instead. Either works as the
        // quality signal between comparable text matches.
        let popularity = min(Double(item.metadata?.popularity ?? 0) / 100, 1)
        let userRating = min((item.metadata?.userRating ?? 0) / 10, 1)
        let qualityScore = max(popularity, userRating)

        // Small nudge for playable catalog content; the winning artist gets
        // its bigger top-slot bonus in `sort`, not here — a flat artist
        // boost would rank every same-named artist above tracks and albums.
        // Scaled by textScore so a boost only lifts items that match.
        let typeBoost: Double
        switch item.content.type {
        case .artist, .album, .track: typeBoost = 0.05
        case .libraryArtist: typeBoost = -0.05
        default: typeBoost = 0
        }

        let historyBoost = recentlyPlayedIDs.contains(item.id) ? historyWeight * text : 0

        let recencyBoost: Double
        if let released = item.metadata?.albumYear {
            let age = now.timeIntervalSince(released)
            recencyBoost = age >= 0 && age < recencyWindow
                ? recencyWeight * (1 - age / recencyWindow) * text
                : 0
        } else {
            recencyBoost = 0
        }

        return text * textWeight
            + qualityScore * popularityWeight
            + typeBoost * text
            + historyBoost
            + recencyBoost
    }

    /// The best text relevance across the item's title (with and without a
    /// version suffix), subtitle, and combined title + subtitle.
    static func textScore(item: PlayableContent, query: String) -> Double {
        var titleScore = textMatchScore(source: item.title, query: query)
        let primary = primaryTitle(of: item.title)
        if primary != item.title {
            titleScore = max(titleScore, textMatchScore(source: primary, query: query) * primaryTitleFactor)
        }
        let subtitleScore = textMatchScore(source: item.subtitle, query: query)
        let combinedScore = textMatchScore(source: "\(item.title) \(item.subtitle)", query: query)

        return max(titleScore, subtitleScore * subtitleFactor, combinedScore * combinedFactor)
    }

    // MARK: - Text matching

    /// Relevance of `query` against `source` in 0...1.
    ///
    /// Tiers: exact (1.0) > prefix (0.9) > whole-word substring (0.8) >
    /// all query words present as prefixes (0.75, typo-tolerant words at a
    /// 0.8 discount) > mid-word substring (0.55) > in-order character
    /// subsequence (≤ 0.4, length-penalized). The old ranking used only the
    /// subsequence, so "Love" and "Lyrics of Vengeance" tied for the query
    /// "love".
    static func textMatchScore(source: String, query: String) -> Double {
        let source = normalized(source)
        let query = normalized(query)
        guard !source.isEmpty, !query.isEmpty else { return 0 }

        if source == query { return 1 }
        if source.hasPrefix(query) { return 0.9 }

        if let range = source.range(of: query) {
            let startsWord = range.lowerBound == source.startIndex
                || source[source.index(before: range.lowerBound)] == " "
            return startsWord ? 0.8 : 0.55
        }

        // Word-level matching: query words found anywhere in the source (any
        // order) count fully as a prefix, or at a discount when they're a
        // close misspelling ("bohemain" for "bohemian"). All words matching
        // as prefixes scores 0.75; typos and subsets scale down from there.
        let queryTokens = query.split(separator: " ")
        let sourceTokens = source.split(separator: " ")
        var tokenCredit = 0.0
        for token in queryTokens {
            if sourceTokens.contains(where: { $0.hasPrefix(token) }) {
                tokenCredit += 1
            } else {
                let tolerance = typoTolerance(for: token)
                if tolerance > 0,
                   sourceTokens.contains(where: { editDistance($0, token, limit: tolerance) <= tolerance }) {
                    tokenCredit += 0.8
                }
            }
        }
        if tokenCredit > 0 {
            return 0.75 * tokenCredit / Double(queryTokens.count)
        }

        // Typo fallback: in-order character subsequence, discounted and
        // length-penalized so scattered characters can't outrank real matches.
        let matchedCharacters = subsequenceMatchCount(source: source, query: query)
        let coverage = Double(matchedCharacters) / Double(query.count)
        guard coverage >= 0.75 else { return 0 }
        let lengthPenalty = Double(query.count) / Double(max(source.count, query.count))
        return 0.4 * coverage * lengthPenalty
    }

    /// Case- and diacritic-insensitive ("beyonce" == "Beyoncé"), apostrophes
    /// removed ("dont" == "Don't"), other punctuation treated as a word break
    /// ("Mr. Brightside" == "mr brightside").
    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var result = ""
        var lastWasSpace = true
        for character in folded {
            if character.isLetter || character.isNumber {
                result.append(character)
                lastWasSpace = false
            } else if character == "'" || character == "\u{2019}" {
                continue
            } else if !lastWasSpace {
                result.append(" ")
                lastWasSpace = true
            }
        }
        if result.hasSuffix(" ") { result.removeLast() }
        return result
    }

    /// Whether `phrase` appears in `text` bounded by word breaks on both
    /// sides — "dua" matches "dua lipa jun 2024" but not "duality". Both
    /// strings must already be normalized.
    private static func matchesWholeWords(_ text: String, phrase: String) -> Bool {
        guard let range = text.range(of: phrase) else { return false }
        let startsWord = range.lowerBound == text.startIndex
            || text[text.index(before: range.lowerBound)] == " "
        let endsWord = range.upperBound == text.endIndex
            || text[range.upperBound] == " "
        return startsWord && endsWord
    }

    /// The title with a trailing version/remix suffix removed:
    /// "Love Story (Taylor's Version)" -> "Love Story",
    /// "Blinding Lights - Radio Edit" -> "Blinding Lights".
    static func primaryTitle(of title: String) -> String {
        var cut = title.endIndex
        for marker in [" (", " [", " - "] {
            if let range = title.range(of: marker), range.lowerBound < cut {
                cut = range.lowerBound
            }
        }
        return cut == title.endIndex ? title : String(title[..<cut])
    }

    /// How many edits a word may be away and still count as a typo of the
    /// query word. Short words get none — "love" must not match "dove".
    static func typoTolerance(for token: Substring) -> Int {
        if token.count >= 8 { return 2 }
        if token.count >= 5 { return 1 }
        return 0
    }

    /// Levenshtein distance, bailing out with `limit + 1` as soon as the
    /// distance is guaranteed to exceed `limit`.
    static func editDistance(_ lhs: Substring, _ rhs: Substring, limit: Int) -> Int {
        let lhs = Array(lhs)
        let rhs = Array(rhs)
        if abs(lhs.count - rhs.count) > limit { return limit + 1 }

        var previousRow = Array(0...rhs.count)
        for (i, lhsCharacter) in lhs.enumerated() {
            var currentRow = [i + 1]
            currentRow.reserveCapacity(rhs.count + 1)
            var rowMinimum = i + 1
            for (j, rhsCharacter) in rhs.enumerated() {
                let substitution = previousRow[j] + (lhsCharacter == rhsCharacter ? 0 : 1)
                let value = min(substitution, previousRow[j + 1] + 1, currentRow[j] + 1)
                currentRow.append(value)
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return limit + 1 }
            previousRow = currentRow
        }
        return previousRow[rhs.count]
    }

    /// Greedy count of query characters found in order within the source.
    static func subsequenceMatchCount(source: String, query: String) -> Int {
        var count = 0
        var sourceIndex = source.startIndex
        for queryCharacter in query {
            guard let found = source[sourceIndex...].firstIndex(of: queryCharacter) else { continue }
            count += 1
            sourceIndex = source.index(after: found)
        }
        return count
    }
}
