import XCTest
@testable import SonosKit

final class SearchRankingTests: XCTestCase {

    // MARK: Helpers

    private func item(
        title: String,
        subtitle: String = "",
        type: ContentType = .track,
        service: MusicService = .spotify,
        popularity: Int? = nil,
        id: String = UUID().uuidString
    ) -> PlayableContent {
        PlayableContent(
            title: title,
            subtitle: subtitle,
            thumbnail: nil,
            artwork: nil,
            content: MediaContent(service: service, id: id, type: type, location: nil),
            metadata: popularity.map { PlayableContentMetadata(popularity: $0) }
        )
    }

    private func titles(_ results: [PlayableContent]) -> [String] {
        results.map(\.title)
    }

    // MARK: Text match tiers

    func testExactMatchBeatsPrefixBeatsWordBeatsScatter() {
        let exact = SearchRanking.textMatchScore(source: "Love", query: "love")
        let prefix = SearchRanking.textMatchScore(source: "Love Story", query: "love")
        let word = SearchRanking.textMatchScore(source: "Crazy in Love", query: "love")
        let midWord = SearchRanking.textMatchScore(source: "Glove", query: "love")
        let scattered = SearchRanking.textMatchScore(source: "Lyrics of Vengeance", query: "love")

        XCTAssertEqual(exact, 1.0)
        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, word)
        XCTAssertGreaterThan(word, midWord)
        XCTAssertGreaterThan(midWord, scattered)
        XCTAssertGreaterThan(scattered, 0)
    }

    func testNoCreditForUnrelatedText() {
        XCTAssertEqual(SearchRanking.textMatchScore(source: "Love", query: "xyz"), 0)
        XCTAssertEqual(SearchRanking.textMatchScore(source: "", query: "love"), 0)
        XCTAssertEqual(SearchRanking.textMatchScore(source: "Love", query: ""), 0)
    }

    func testMultiWordQueryMatchesTokensInAnyOrder() {
        let allTokens = SearchRanking.textMatchScore(source: "Queen Bohemian Rhapsody", query: "rhapsody queen")
        let someTokens = SearchRanking.textMatchScore(source: "Rhapsody in Blue", query: "rhapsody queen")

        XCTAssertEqual(allTokens, 0.75)
        XCTAssertGreaterThan(allTokens, someTokens)
        XCTAssertGreaterThan(someTokens, 0)
    }

    func testDiacriticsAndPunctuationAreIgnored() {
        XCTAssertEqual(SearchRanking.textMatchScore(source: "Beyoncé", query: "beyonce"), 1.0)
        XCTAssertEqual(SearchRanking.textMatchScore(source: "Don't Stop Me Now", query: "dont stop me now"), 1.0)
        XCTAssertEqual(SearchRanking.textMatchScore(source: "Mr. Brightside", query: "mr brightside"), 1.0)
    }

    func testTypoToleranceMatchesMisspellings() {
        let artistTypo = SearchRanking.textMatchScore(source: "Beyoncé", query: "beyonse")
        XCTAssertEqual(artistTypo, 0.6, accuracy: 0.001)

        let transposition = SearchRanking.textMatchScore(source: "Bohemian Rhapsody", query: "bohemain rhapsody")
        XCTAssertEqual(transposition, 0.675, accuracy: 0.001)
    }

    func testShortWordsGetNoTypoTolerance() {
        // "love" must not count "Dove" as a typo; only the weak
        // subsequence fallback may apply.
        XCTAssertLessThan(SearchRanking.textMatchScore(source: "Dove", query: "love"), 0.5)
        XCTAssertEqual(SearchRanking.typoTolerance(for: "love"), 0)
        XCTAssertEqual(SearchRanking.typoTolerance(for: "queen"), 1)
        XCTAssertEqual(SearchRanking.typoTolerance(for: "bohemian"), 2)
    }

    func testEditDistance() {
        XCTAssertEqual(SearchRanking.editDistance("bohemian", "bohemain", limit: 2), 2)
        XCTAssertEqual(SearchRanking.editDistance("beyonce", "beyonse", limit: 1), 1)
        XCTAssertEqual(SearchRanking.editDistance("queen", "queen", limit: 1), 0)
        // Bails out early when the distance exceeds the limit.
        XCTAssertGreaterThan(SearchRanking.editDistance("somebody", "rhapsody", limit: 2), 2)
    }

    func testPrimaryTitleStripsVersionSuffixes() {
        XCTAssertEqual(SearchRanking.primaryTitle(of: "Love Story (Taylor's Version)"), "Love Story")
        XCTAssertEqual(SearchRanking.primaryTitle(of: "Blinding Lights - Radio Edit"), "Blinding Lights")
        XCTAssertEqual(SearchRanking.primaryTitle(of: "Time [Remastered 2011]"), "Time")
        XCTAssertEqual(SearchRanking.primaryTitle(of: "(I Can't Get No) Satisfaction"), "(I Can't Get No) Satisfaction")
        XCTAssertEqual(SearchRanking.primaryTitle(of: "Plain Title"), "Plain Title")
    }

    func testNormalized() {
        XCTAssertEqual(SearchRanking.normalized("Mr. Brightside"), "mr brightside")
        XCTAssertEqual(SearchRanking.normalized("Don't Stop Me Now"), "dont stop me now")
        XCTAssertEqual(SearchRanking.normalized("Beyoncé"), "beyonce")
        XCTAssertEqual(SearchRanking.normalized("  AC/DC  "), "ac dc")
    }

    // MARK: Weighting

    func testExactTitleMatchOutranksScatteredCharacterMatch() {
        // The old subsequence-only scoring gave these identical title scores.
        let results = SearchRanking.sort(
            [
                item(title: "Lyrics of Vengeance"),
                item(title: "Love"),
            ],
            query: "love"
        )
        XCTAssertEqual(titles(results), ["Love", "Lyrics of Vengeance"])
    }

    func testPopularityCannotOutrankTextRelevance() {
        let results = SearchRanking.sort(
            [
                item(title: "Glove", popularity: 100),
                item(title: "Love", popularity: 0),
            ],
            query: "love"
        )
        XCTAssertEqual(titles(results), ["Love", "Glove"])
    }

    func testPopularityBreaksTiesBetweenComparableMatches() {
        let results = SearchRanking.sort(
            [
                item(title: "Somebody to Love", subtitle: "Queen", popularity: 60),
                item(title: "Bohemian Rhapsody", subtitle: "Queen", popularity: 95),
            ],
            query: "queen"
        )
        XCTAssertEqual(titles(results), ["Bohemian Rhapsody", "Somebody to Love"])
    }

    func testArtistSearchRanksLikeSpotify() {
        let results = SearchRanking.sort(
            [
                item(title: "Killer Queen", subtitle: "Queen", popularity: 80),
                item(title: "The Queen Collection", subtitle: "Various Artists", type: .album),
                item(title: "Bohemian Rhapsody", subtitle: "Queen", popularity: 95),
                item(title: "Queen", subtitle: "Jessie J", popularity: 70),
                item(title: "Queen", subtitle: "Artist", type: .artist),
            ],
            query: "queen"
        )

        // Artist first, then the exact-title track, then the artist's tracks
        // by popularity, then weaker title matches.
        XCTAssertEqual(results.first?.content.type, .artist)
        XCTAssertEqual(
            titles(results),
            ["Queen", "Queen", "Bohemian Rhapsody", "Killer Queen", "The Queen Collection"]
        )
        XCTAssertEqual(results[1].subtitle, "Jessie J")
    }

    func testSongPlusArtistQueryFindsTheTrack() {
        let results = SearchRanking.sort(
            [
                item(title: "Rhapsody in Blue", subtitle: "Gershwin", popularity: 50),
                item(title: "Bohemian Rhapsody", subtitle: "Queen", popularity: 50),
            ],
            query: "rhapsody queen"
        )
        XCTAssertEqual(titles(results), ["Bohemian Rhapsody", "Rhapsody in Blue"])
    }

    func testPrefixTitleBeatsMidWordMatch() {
        let results = SearchRanking.sort(
            [
                item(title: "Superstar"),
                item(title: "Starman"),
            ],
            query: "star"
        )
        XCTAssertEqual(titles(results), ["Starman", "Superstar"])
    }

    func testVersionSuffixDoesNotDiluteExactMatch() {
        let results = SearchRanking.sort(
            [
                item(title: "Love Story and More"),
                item(title: "Love Story (Taylor's Version)"),
            ],
            query: "love story"
        )
        // Both are prefix matches on the full title, but stripping the
        // version suffix makes the second an (almost) exact match.
        XCTAssertEqual(titles(results), ["Love Story (Taylor's Version)", "Love Story and More"])
    }

    func testRecentlyPlayedItemWinsAmongComparableMatches() {
        let played = item(title: "Fat Bottomed Girls", subtitle: "Queen", popularity: 60, id: "played-id")
        let notPlayed = item(title: "Bohemian Rhapsody", subtitle: "Queen", popularity: 95)

        let results = SearchRanking.sort(
            [notPlayed, played],
            query: "queen",
            recentlyPlayedIDs: ["played-id"]
        )
        XCTAssertEqual(titles(results), ["Fat Bottomed Girls", "Bohemian Rhapsody"])
    }

    func testRecentlyPlayedCannotOutrankBetterTextMatch() {
        let results = SearchRanking.sort(
            [
                item(title: "Bohemian Rhapsody", subtitle: "Queen", type: .track, id: "played-id"),
                item(title: "Queen", subtitle: "Artist", type: .artist),
            ],
            query: "queen",
            recentlyPlayedIDs: ["played-id"]
        )
        XCTAssertEqual(results.first?.content.type, .artist)
    }

    func testUserRatingActsAsQualitySignalWhenPopularityMissing() {
        let rated = PlayableContent(
            title: "Rated Track",
            subtitle: "Queen",
            thumbnail: nil,
            artwork: nil,
            content: MediaContent(service: .plex, id: "rated", type: .track, location: nil),
            metadata: PlayableContentMetadata(userRating: 10)
        )
        let unrated = item(title: "Unrated Track", subtitle: "Queen", service: .plex)

        let results = SearchRanking.sort([unrated, rated], query: "queen")
        XCTAssertEqual(titles(results), ["Rated Track", "Unrated Track"])
    }

    // MARK: Multiservice merge

    func testMergedSearchCollapsesCrossServiceDuplicates() {
        let libraryTrack = item(title: "Bohemian Rhapsody", subtitle: "Queen", service: .library, id: "lib-1")
        let appleTrack = item(title: "Bohemian Rhapsody", subtitle: "Queen", service: .apple, id: "apple-1")

        let merged = SearchRanking.sort([libraryTrack, appleTrack], query: "queen", mergingServices: true)
        XCTAssertEqual(merged.count, 1)
        // On a scoring tie, prefer the streaming catalog over the library.
        XCTAssertEqual(merged.first?.content.service, .apple)

        // Without merging, service-specific IDs keep both.
        let unmerged = SearchRanking.sort([libraryTrack, appleTrack], query: "queen")
        XCTAssertEqual(unmerged.count, 2)
    }

    func testMergedSearchCollapsesLibraryAndCatalogTypeVariants() {
        let libraryAlbum = item(title: "A Night at the Opera", subtitle: "Queen", type: .libraryAlbum, service: .library, id: "lib-album")
        let catalogAlbum = item(title: "A Night at the Opera", subtitle: "Queen", type: .album, service: .apple, id: "apple-album")

        let merged = SearchRanking.sort([libraryAlbum, catalogAlbum], query: "queen", mergingServices: true)
        XCTAssertEqual(merged.count, 1)
    }

    func testMergedSearchKeepsDifferentKindsApart() {
        let artist = item(title: "Queen", type: .artist, service: .apple, id: "artist-1")
        let track = item(title: "Queen", type: .track, service: .library, id: "track-1")

        let merged = SearchRanking.sort([artist, track], query: "queen", mergingServices: true)
        XCTAssertEqual(merged.count, 2)
    }

    func testMergedSearchKeepsHigherScoredDuplicate() {
        let libraryTrack = item(title: "Bohemian Rhapsody", subtitle: "Queen", service: .library, id: "lib-1")
        let spotifyTrack = item(title: "Bohemian Rhapsody", subtitle: "Queen", service: .spotify, popularity: 90, id: "sp-1")

        let merged = SearchRanking.sort([libraryTrack, spotifyTrack], query: "queen", mergingServices: true)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.content.service, .spotify)
    }

    // MARK: Dedup & stability

    func testDuplicatesAreRemoved() {
        let duplicate = item(title: "Love", subtitle: "Artist", id: "same-id")
        let results = SearchRanking.sort([duplicate, duplicate], query: "love")
        XCTAssertEqual(results.count, 1)
    }

    func testEqualScoresPreserveIncomingOrder() {
        let results = SearchRanking.sort(
            [
                item(title: "Zebra"),
                item(title: "Apple"),
            ],
            query: "unrelated query"
        )
        XCTAssertEqual(titles(results), ["Zebra", "Apple"])
    }

    func testServiceRelevanceOrderKeptWithoutPopularityData() {
        // Apple Music reports no popularity, so an artist's tracks all tie on
        // the subtitle match — the API's own relevance order must survive.
        let results = SearchRanking.sort(
            [
                item(title: "Bohemian Rhapsody", subtitle: "Queen", service: .apple),
                item(title: "Another One Bites the Dust", subtitle: "Queen", service: .apple),
                item(title: "Somebody to Love", subtitle: "Queen", service: .apple),
            ],
            query: "queen"
        )
        XCTAssertEqual(
            titles(results),
            ["Bohemian Rhapsody", "Another One Bites the Dust", "Somebody to Love"]
        )
    }
}
