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
        albumYear: Date? = nil,
        id: String = UUID().uuidString
    ) -> PlayableContent {
        let metadata: PlayableContentMetadata? = popularity != nil || albumYear != nil
            ? PlayableContentMetadata(popularity: popularity, albumYear: albumYear)
            : nil
        return PlayableContent(
            title: title,
            subtitle: subtitle,
            thumbnail: nil,
            artwork: nil,
            content: MediaContent(service: service, id: id, type: type, location: nil),
            metadata: metadata
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
        // Fullwidth characters (common in Japanese catalog titles) fold to
        // their ASCII forms.
        XCTAssertEqual(SearchRanking.normalized("ＡＢＢＡ"), "abba")
    }

    func testWordStartMatchDetectedAtAnyOccurrence() {
        // The first occurrence is mid-word; the later word-start occurrence
        // must still earn the whole-word tier.
        XCTAssertEqual(SearchRanking.textMatchScore(source: "Supermarket Market", query: "market"), 0.8)
    }

    func testMisspelledArtistQueryStillCrownsTheArtist() {
        let results = SearchRanking.sort(
            [
                item(title: "Halo", subtitle: "Beyoncé", popularity: 85),
                item(title: "Beyoncé", subtitle: "Artist", type: .artist, popularity: 95, id: "artist"),
            ],
            query: "beyonse"
        )
        XCTAssertEqual(results.first?.id, "artist")
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
                item(title: "Queen", subtitle: "Artist", type: .artist, popularity: 89),
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

    func testPopularArtistAndTheirHitsOutrankObscureExactNameArtists() {
        // Searching "dua" on Spotify must not show a wall of artists named
        // "Dua": the popular artist takes the top slot, and her popular
        // tracks/albums beat obscure artists whose name merely matches better.
        let results = SearchRanking.sort(
            [
                item(title: "Dua", subtitle: "Artist", type: .artist, popularity: 25, id: "dua-1"),
                item(title: "Dua", subtitle: "Artist", type: .artist, popularity: 15, id: "dua-2"),
                item(title: "Dua Lipa", subtitle: "Artist", type: .artist, popularity: 90, id: "dua-lipa"),
                item(title: "Houdini", subtitle: "Dua Lipa", popularity: 85),
                item(title: "Radical Optimism", subtitle: "Dua Lipa", type: .album, popularity: 78),
            ],
            query: "dua"
        )

        XCTAssertEqual(
            titles(results),
            ["Dua Lipa", "Houdini", "Dua", "Radical Optimism", "Dua"]
        )
        XCTAssertEqual(results.first?.id, "dua-lipa")
    }

    func testTopArtistAlbumsInheritArtistPopularity() {
        // Spotify's search API reports no popularity for albums, so the
        // focused artist's albums must borrow the artist's popularity to
        // surface alongside the tracks instead of sinking below them.
        let results = SearchRanking.sort(
            [
                item(title: "Dua", subtitle: "Artist", type: .artist, popularity: 25, id: "dua-obscure"),
                item(title: "Dua Lipa", subtitle: "Artist", type: .artist, popularity: 90, id: "dua-lipa"),
                item(title: "Houdini", subtitle: "Dua Lipa", popularity: 85),
                item(title: "Radical Optimism", subtitle: "Dua Lipa • Jun 2024", type: .album, id: "album"),
            ],
            query: "dua"
        )

        XCTAssertEqual(
            titles(results),
            ["Dua Lipa", "Radical Optimism", "Houdini", "Dua"]
        )
    }

    func testNewReleaseGetsSlightBoost() {
        let now = Date()
        let fresh = item(
            title: "Comeback",
            subtitle: "Artist",
            type: .album,
            albumYear: now.addingTimeInterval(-30 * 24 * 60 * 60),
            id: "fresh"
        )
        let old = item(
            title: "Comeback",
            subtitle: "Artist",
            type: .album,
            albumYear: now.addingTimeInterval(-10 * 365 * 24 * 60 * 60),
            id: "old"
        )

        let results = SearchRanking.sort([old, fresh], query: "comeback", now: now)
        XCTAssertEqual(results.map(\.id), ["fresh", "old"])
    }

    func testSongTitleQueryDoesNotCrownObscureArtist() {
        // "just dance" means the Lady Gaga song — an unknown artist who
        // happens to share the name must not take the top slot.
        let results = SearchRanking.sort(
            [
                item(title: "Just Dance", subtitle: "Artist", type: .artist, popularity: 20, id: "obscure-artist"),
                item(title: "Just Dance", subtitle: "Lady Gaga, Colby O'Donis", popularity: 80, id: "hit-song"),
            ],
            query: "just dance"
        )
        XCTAssertEqual(results.first?.id, "hit-song")
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
        let notPlayed = item(title: "Bohemian Rhapsody", subtitle: "Queen", popularity: 90)

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

    // MARK: Multi-service artist grouping

    func testMultiServiceGroupsMatchingArtistsAtTop() {
        // The same artist appears once per service; grouping lifts every copy
        // above tracks that only match on the artist line, even the
        // lower-popularity copy.
        let spotifyArtist = item(title: "Adele", subtitle: "Artist", type: .artist, service: .spotify, popularity: 90, id: "sp-artist")
        let appleArtist = item(title: "Adele", subtitle: "Artist", type: .artist, service: .apple, popularity: 45, id: "ap-artist")
        let track = item(title: "Hello", subtitle: "Adele", service: .spotify, popularity: 95, id: "hello")
        let items = [spotifyArtist, track, appleArtist]

        let grouped = SearchRanking.sort(items, query: "adele", groupArtists: true)
        XCTAssertEqual(grouped.map(\.content.type), [.artist, .artist, .track])
        XCTAssertEqual(grouped.first?.id, "sp-artist")

        // Single-service mode boosts only the best artist, so the
        // lower-popularity copy falls below the popular track.
        let single = SearchRanking.sort(items, query: "adele")
        XCTAssertEqual(single.map(\.id), ["sp-artist", "hello", "ap-artist"])
    }

    func testArtistOutranksSelfTitledAlbumsEvenWithoutOwnPopularity() {
        // The "dua lipa" regression: self-titled albums match the query title
        // exactly, and the Apple artist copy reports no popularity. The artist
        // rows must still rank above the albums by borrowing the Spotify
        // copy's popularity.
        let appleArtist = item(title: "Dua Lipa", subtitle: "Artist", type: .artist, service: .apple, id: "apple-artist")
        let spotifyArtist = item(title: "Dua Lipa", subtitle: "Artist", type: .artist, service: .spotify, popularity: 90, id: "spotify-artist")
        let appleAlbum = item(title: "Dua Lipa", subtitle: "Dua Lipa", type: .album, service: .apple, id: "apple-album")
        let deluxe = item(title: "Dua Lipa (Deluxe)", subtitle: "Dua Lipa", type: .album, service: .apple, id: "deluxe-album")

        let results = SearchRanking.sort(
            [appleAlbum, deluxe, appleArtist, spotifyArtist],
            query: "dua lipa",
            groupArtists: true
        )
        // Both artist rows come before any album.
        let firstAlbumIndex = results.firstIndex { $0.content.type == .album } ?? results.count
        let artistIndices = results.enumerated().filter { $0.element.content.type == .artist }.map(\.offset)
        XCTAssertEqual(artistIndices.count, 2)
        XCTAssertTrue(artistIndices.allSatisfy { $0 < firstAlbumIndex })
    }

    func testGroupingStillKeepsObscureSameNamedArtistsDown() {
        // Grouping scales purely by popularity, so a nobody sharing a song's
        // name can't ride to the top — the hit song stays first.
        let results = SearchRanking.sort(
            [
                item(title: "Just Dance", subtitle: "Artist", type: .artist, service: .apple, popularity: 20, id: "obscure-artist"),
                item(title: "Just Dance", subtitle: "Lady Gaga, Colby O'Donis", service: .spotify, popularity: 80, id: "hit-song"),
            ],
            query: "just dance",
            groupArtists: true
        )
        XCTAssertEqual(results.first?.id, "hit-song")
    }

    // MARK: Dedup & stability

    func testSameContentFromDifferentSourcesIsNotDeduplicated() {
        // The "same" song from two services (or the library and a catalog,
        // or two Plex sections) must stay visible so the user picks which
        // copy to play — and downstream filters (like Plex's per-section
        // filter) never lose the copy they needed.
        let libraryCopy = item(title: "Bohemian Rhapsody", subtitle: "Queen", service: .library, id: "lib-1")
        let appleCopy = item(title: "Bohemian Rhapsody", subtitle: "Queen", service: .apple, id: "apple-1")

        let results = SearchRanking.sort([libraryCopy, appleCopy], query: "queen")
        XCTAssertEqual(results.count, 2)
    }

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

    func testSortIsIdempotent() {
        // The search screen keeps results on screen across navigation; any
        // re-sort of an already-ranked list (e.g. a provider re-publishing)
        // must reproduce the identical order — ties break on input position,
        // so re-sorting sorted output is a fixed point. Duplicate same-scoring
        // items (an artist's many equal albums) are the regression case.
        let input = [
            item(title: "Dua Lipa", subtitle: "Dua Lipa • 2017", type: .album, service: .plex, id: "edition-1"),
            item(title: "Dua Lipa", subtitle: "Dua Lipa • 2017", type: .album, service: .plex, id: "edition-2"),
            item(title: "Dua Lipa", subtitle: "Dua Lipa • 2017", type: .album, service: .plex, id: "edition-3"),
            item(title: "Dua Lipa", type: .artist, service: .spotify, popularity: 90, id: "artist"),
            item(title: "Future Nostalgia", subtitle: "Dua Lipa", type: .album, service: .spotify, popularity: 80, id: "fn"),
        ]

        let once = SearchRanking.sort(input, query: "dua lipa", groupArtists: true)
        let twice = SearchRanking.sort(once, query: "dua lipa", groupArtists: true)
        XCTAssertEqual(titles(twice), titles(once))
        XCTAssertEqual(twice.map(\.id), once.map(\.id))
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
