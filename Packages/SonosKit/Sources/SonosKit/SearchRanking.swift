import Foundation

/// Scores and orders search results so ranking feels like a first-party music
/// app (Spotify / Apple Music): exact and prefix title matches first, then
/// whole-word matches, with popularity breaking ties between comparable
/// matches and artists nudged above same-named tracks/albums.
///
/// Scoring is service-agnostic and produces scores comparable across services,
/// so a future multiservice (merged) search can rank one combined list.
enum SearchRanking {

    /// Deduplicates and sorts content by relevance score (descending). Ties
    /// keep the incoming order: services already return relevance-ordered
    /// results, so equal-scoring items shouldn't be scrambled alphabetically.
    static func sort(
        _ playableContent: [PlayableContent],
        query: String,
        recentlyPlayedIDs: Set<String> = []
    ) -> [PlayableContent] {
        var uniqueItems: [String: (item: PlayableContent, score: Double, index: Int)] = [:]

        for (index, item) in playableContent.enumerated() {
            let itemScore = score(item: item, query: query, recentlyPlayedIDs: recentlyPlayedIDs)
            let key = "\(item.id)-\(item.title)-\(item.subtitle)"
            if let existing = uniqueItems[key] {
                if itemScore > existing.score {
                    uniqueItems[key] = (item, itemScore, existing.index)
                }
            } else {
                uniqueItems[key] = (item, itemScore, index)
            }
        }

        return uniqueItems.values
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
    /// Popularity only orders results whose text matches are comparable.
    /// Spotify is the main service that reports it; others leave it nil.
    private static let popularityWeight = 0.15
    /// A match on the subtitle (artist/album line) is meaningful but weaker
    /// than a match on the item's own title.
    private static let subtitleFactor = 0.85
    /// Matches that need title + subtitle combined ("rhapsody queen").
    private static let combinedFactor = 0.9
    /// Matching the title with its version suffix stripped ("Love Story
    /// (Taylor's Version)" for the query "love story") is nearly as good as
    /// matching the full title.
    private static let primaryTitleFactor = 0.97
    /// Items the user has actually played rise above comparable matches.
    private static let historyWeight = 0.1

    static func score(item: PlayableContent, query: String, recentlyPlayedIDs: Set<String> = []) -> Double {
        var titleScore = textMatchScore(source: item.title, query: query)
        let primary = primaryTitle(of: item.title)
        if primary != item.title {
            titleScore = max(titleScore, textMatchScore(source: primary, query: query) * primaryTitleFactor)
        }
        let subtitleScore = textMatchScore(source: item.subtitle, query: query)
        let combinedScore = textMatchScore(source: "\(item.title) \(item.subtitle)", query: query)

        let textScore = max(titleScore, subtitleScore * subtitleFactor, combinedScore * combinedFactor)

        // Spotify reports popularity (0-100); Plex and the local library
        // report user star ratings (0-10) instead. Either works as the
        // quality tiebreaker between comparable text matches.
        let popularity = min(Double(item.metadata?.popularity ?? 0) / 100, 1)
        let userRating = min((item.metadata?.userRating ?? 0) / 10, 1)
        let qualityScore = max(popularity, userRating)

        // Searching a name should surface the artist above same-named tracks,
        // the way Spotify/Apple do. Scaled by textScore below so a boost can
        // only lift items that actually match the query.
        let typeBoost: Double
        switch item.content.type {
        case .artist: typeBoost = 0.25
        case .album, .track: typeBoost = 0.05
        case .libraryArtist: typeBoost = -0.05
        default: typeBoost = 0
        }

        let historyBoost = recentlyPlayedIDs.contains(item.id) ? historyWeight * textScore : 0

        return textScore * textWeight
            + qualityScore * popularityWeight
            + typeBoost * textScore
            + historyBoost
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
