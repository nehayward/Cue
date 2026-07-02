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
    static func sort(_ playableContent: [PlayableContent], query: String) -> [PlayableContent] {
        var uniqueItems: [String: (item: PlayableContent, score: Double, index: Int)] = [:]

        for (index, item) in playableContent.enumerated() {
            let itemScore = score(item: item, query: query)
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

    static func score(item: PlayableContent, query: String) -> Double {
        let titleScore = textMatchScore(source: item.title, query: query)
        let subtitleScore = textMatchScore(source: item.subtitle, query: query)
        let combinedScore = textMatchScore(source: "\(item.title) \(item.subtitle)", query: query)

        let textScore = max(titleScore, subtitleScore * subtitleFactor, combinedScore * combinedFactor)

        let popularity = min(Double(item.metadata?.popularity ?? 0) / 100, 1)

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

        return textScore * textWeight
            + popularity * popularityWeight
            + typeBoost * textScore
    }

    // MARK: - Text matching

    /// Relevance of `query` against `source` in 0...1.
    ///
    /// Tiers: exact (1.0) > prefix (0.9) > whole-word substring (0.8) >
    /// all query words present (0.75) > mid-word substring (0.55) > in-order
    /// character subsequence (≤ 0.4, length-penalized). The old ranking used
    /// only the subsequence, so "Love" and "Lyrics of Vengeance" tied for the
    /// query "love".
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

        // Multi-word query: every word matching somewhere in the source (any
        // order) is still a strong match; a subset gets partial credit.
        let queryTokens = query.split(separator: " ")
        if queryTokens.count > 1 {
            let sourceTokens = source.split(separator: " ")
            let matched = queryTokens.filter { token in
                sourceTokens.contains { $0.hasPrefix(token) }
            }
            if matched.count == queryTokens.count { return 0.75 }
            if !matched.isEmpty { return 0.5 * Double(matched.count) / Double(queryTokens.count) }
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
