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
        groupArtists: Bool = false,
        now: Date = Date()
    ) -> [PlayableContent] {
        // Normalized once here; every per-item comparison reuses it.
        let normalizedQuery = normalized(query)
        var uniqueItems: [String: (item: PlayableContent, score: Double, index: Int)] = [:]

        for (index, item) in playableContent.enumerated() {
            let itemScore = score(item: item, normalizedQuery: normalizedQuery, recentlyPlayedIDs: recentlyPlayedIDs, now: now)
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

        // The same artist appears across services with popularity on only
        // some copies — Spotify reports it, MusicKit doesn't, the library
        // doesn't. Share each artist's best-known popularity across its copies
        // (keyed by name) so every copy earns the same top-artist bonus and
        // the artist's albums inherit a consistent quality signal. Without
        // this, an Apple "Dua Lipa" (popularity 0) sank below its own
        // self-titled albums, which match the query title just as exactly.
        var artistPopularity: [String: Double] = [:]
        for index in entries.indices where entries[index].item.content.type.isArtist {
            let name = normalized(entries[index].item.title)
            guard !name.isEmpty else { continue }
            let pop = min(Double(entries[index].item.metadata?.popularity ?? 0) / 100, 1)
            artistPopularity[name] = max(artistPopularity[name] ?? 0, pop)
        }

        // Artist boost: lift matching artists toward the top like Spotify's
        // top result. Single-service search boosts only the best-matching
        // artist — a flat boost would wall tracks and albums behind a run of
        // same-named artists (searching "dua" must rank Dua Lipa and her hits
        // above ten obscure artists named "Dua"). A merged multi-service
        // search instead groups every matching artist, since the same artist
        // legitimately appears once per service; popularity scaling keeps
        // obscure same-named artists from riding along.
        let matchingArtists = entries.indices
            .filter { entries[$0].item.content.type.isArtist }
            .map { (index: $0, text: textScore(item: entries[$0].item, normalizedQuery: normalizedQuery)) }
            .filter { $0.text >= topArtistMinimumText }

        let boostedArtists: [(index: Int, text: Double)]
        if groupArtists {
            boostedArtists = matchingArtists
        } else {
            boostedArtists = matchingArtists
                .max { lhs, rhs in
                    if entries[lhs.index].score != entries[rhs.index].score {
                        return entries[lhs.index].score < entries[rhs.index].score
                    }
                    return lhs.index > rhs.index
                }
                .map { [$0] } ?? []
        }

        var boostedArtistNames: Set<String> = []
        for (index, text) in boostedArtists {
            let name = normalized(entries[index].item.title)
            boostedArtistNames.insert(name)
            let quality = artistPopularity[name] ?? 0

            // Level this copy up to the artist's best-known popularity first:
            // a copy from a service that reports none (MusicKit, library)
            // would otherwise score below its own self-titled albums, which
            // inherit that same popularity below.
            let ownQuality = min(Double(entries[index].item.metadata?.popularity ?? 0) / 100, 1)
            entries[index].score += max(0, quality - ownQuality) * popularityWeight

            // Then the top-artist bonus on top, so the artist row always sits
            // above its albums. Single mode uses a 0.5 floor so the one chosen
            // artist reliably beats hit tracks even when only moderately
            // popular; grouping scales purely by popularity so a nobody sharing
            // the name isn't lifted — "just dance" still means the Lady Gaga song.
            let scale = groupArtists ? quality : (0.5 + 0.5 * quality)
            entries[index].score += topArtistBonus * text * scale
        }

        // Albums by a boosted artist that report no popularity of their own
        // (MusicKit, library) inherit the artist's popularity — once each, so
        // they surface alongside the artist's tracks but stay below the artist
        // rows, which additionally carry the bonus above.
        for index in entries.indices {
            let candidate = entries[index].item
            guard candidate.content.type == .album || candidate.content.type == .libraryAlbum,
                  (candidate.metadata?.popularity ?? 0) == 0 else { continue }
            let albumArtist = normalized(candidate.metadata?.artist ?? candidate.subtitle)
            guard let matched = boostedArtistNames.first(where: { matchesWholeWords(albumArtist, phrase: $0) })
            else { continue }
            entries[index].score += (artistPopularity[matched] ?? 0) * popularityWeight
        }

        let ranked = entries
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.index < rhs.index
            }
            .map { $0.item }

        return pinArtistRadios(ranked)
    }

    /// Moves each artist-radio row directly beneath its artist. A radio
    /// carries the artist's own name and popularity, so ranked on its own it
    /// strands between the artist's albums — "Dua Lipa Radio" reads as part
    /// of "Dua Lipa". Pins after the *last* consecutive same-named artist so
    /// a grouped multi-service artist cluster stays intact; radios without a
    /// matching artist row keep their ranked position.
    private static func pinArtistRadios(_ items: [PlayableContent]) -> [PlayableContent] {
        var artistNames: Set<String> = []
        for item in items where item.content.type.isArtist {
            artistNames.insert(normalized(item.title))
        }
        guard !artistNames.isEmpty else { return items }

        var pinned: [String: [PlayableContent]] = [:]
        var rest: [PlayableContent] = []
        for item in items {
            let name = normalized(item.title)
            if item.content.type == .artistRadio, artistNames.contains(name) {
                pinned[name, default: []].append(item)
            } else {
                rest.append(item)
            }
        }
        guard !pinned.isEmpty else { return items }

        var result: [PlayableContent] = []
        result.reserveCapacity(items.count)
        for (index, item) in rest.enumerated() {
            result.append(item)
            guard item.content.type.isArtist else { continue }
            let name = normalized(item.title)
            let nextIsSameArtist = index + 1 < rest.count
                && rest[index + 1].content.type.isArtist
                && normalized(rest[index + 1].title) == name
            if !nextIsSameArtist, let radios = pinned.removeValue(forKey: name) {
                result.append(contentsOf: radios)
            }
        }
        return result
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
    /// An artist must actually match this well before it can take the top
    /// slot. Set at the typo tier (0.75 × 0.8) so a misspelled artist query
    /// ("beyonse") still crowns the artist — the popularity scaling on the
    /// bonus is what keeps junk artists out of the slot.
    private static let topArtistMinimumText = 0.6
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
        score(item: item, normalizedQuery: normalized(query), recentlyPlayedIDs: recentlyPlayedIDs, now: now)
    }

    private static func score(
        item: PlayableContent,
        normalizedQuery: String,
        recentlyPlayedIDs: Set<String>,
        now: Date
    ) -> Double {
        let text = textScore(item: item, normalizedQuery: normalizedQuery)

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
        textScore(item: item, normalizedQuery: normalized(query))
    }

    private static func textScore(item: PlayableContent, normalizedQuery: String) -> Double {
        var titleScore = textMatchScore(source: item.title, normalizedQuery: normalizedQuery)
        let primary = primaryTitle(of: item.title)
        if primary != item.title {
            titleScore = max(titleScore, textMatchScore(source: primary, normalizedQuery: normalizedQuery) * primaryTitleFactor)
        }
        let subtitleScore = textMatchScore(source: item.subtitle, normalizedQuery: normalizedQuery)
        let combinedScore = textMatchScore(source: "\(item.title) \(item.subtitle)", normalizedQuery: normalizedQuery)

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
        textMatchScore(source: source, normalizedQuery: normalized(query))
    }

    private static func textMatchScore(source: String, normalizedQuery: String) -> Double {
        let source = normalized(source)
        let query = normalizedQuery
        guard !source.isEmpty, !query.isEmpty else { return 0 }

        if source == query { return 1 }
        if source.hasPrefix(query) { return 0.9 }

        if source.range(of: query) != nil {
            // Word-start occurrences can appear after a mid-word one
            // ("Supermarket Market" for "market"), so check via padding
            // instead of only inspecting the first range.
            let startsWord = (" " + source).contains(" " + query)
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

    /// Case-, diacritic-, and width-insensitive ("beyonce" == "Beyoncé",
    /// fullwidth "ＡＢＢＡ" == "abba"), apostrophes removed ("dont" ==
    /// "Don't"), other punctuation treated as a word break ("Mr. Brightside"
    /// == "mr brightside").
    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
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
    /// sides — "dua" matches "dua lipa jun 2024" but not "duality". Padded
    /// containment checks every occurrence, not just the first. Both strings
    /// must already be normalized.
    private static func matchesWholeWords(_ text: String, phrase: String) -> Bool {
        (" " + text + " ").contains(" " + phrase + " ")
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
