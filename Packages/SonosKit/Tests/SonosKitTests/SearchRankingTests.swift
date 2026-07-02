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
