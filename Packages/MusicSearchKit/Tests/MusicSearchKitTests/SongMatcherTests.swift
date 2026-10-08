@testable import MusicSearchKit
import XCTest

final class SongMatcherTests: XCTestCase {

    private func track(_ title: String, _ artists: [String], album: String? = nil, duration: TimeInterval? = nil, isrc: String? = nil) -> ImportedTrack {
        ImportedTrack(id: 0, title: title, artists: artists, album: album, duration: duration, isrc: isrc)
    }

    private func confidence(_ track: ImportedTrack, _ candidate: SongCandidate) -> SongMatcher.Confidence? {
        SongMatcher.score(track, candidate).map(SongMatcher.Confidence.init(score:))
    }

    // MARK: - Same song

    func testRemasterSuffixIsIgnored() {
        let source = track("Bohemian Rhapsody - Remastered 2011", ["Queen"], duration: 354)
        let candidate = SongCandidate(title: "Bohemian Rhapsody", artist: "Queen", duration: 355)
        XCTAssertEqual(confidence(source, candidate), .high)
    }

    func testSeveralArtistsAgainstOneLine() {
        let source = track("Under Pressure", ["Queen", "David Bowie"], duration: 248)
        let candidate = SongCandidate(title: "Under Pressure", artist: "Queen & David Bowie", duration: 248)
        XCTAssertEqual(SongMatcher.score(source, candidate), 1)
    }

    func testLeadArtistAloneStillMatches() {
        let source = track("Sweet Dreams (Are Made of This) - 2005 Remaster", ["Eurythmics", "Annie Lennox", "Dave Stewart"])
        let candidate = SongCandidate(title: "Sweet Dreams (Are Made of This)", artist: "Eurythmics")
        XCTAssertEqual(confidence(source, candidate), .high)
    }

    func testBracketedPartOfTitleOnOneSideOnly() {
        let source = track("Sweet Dreams (Are Made of This)", ["Eurythmics"])
        let candidate = SongCandidate(title: "Sweet Dreams Are Made of This", artist: "Eurythmics")
        XCTAssertEqual(confidence(source, candidate), .high)
    }

    func testFeaturingInTitleIsIgnored() {
        let source = track("SICKO MODE", ["Travis Scott"])
        XCTAssertEqual(confidence(source, SongCandidate(title: "SICKO MODE (feat. Drake)", artist: "Travis Scott")), .high)
        XCTAssertEqual(confidence(source, SongCandidate(title: "Sicko Mode feat. Drake", artist: "Travis Scott")), .high)
    }

    func testAccentsCaseAndPunctuation() {
        let source = track("Don't Stop Me Now", ["Beyoncé"])
        let candidate = SongCandidate(title: "dont stop me now", artist: "BEYONCE")
        XCTAssertEqual(SongMatcher.score(source, candidate), 1)
    }

    func testAmpersandAndTheAreFolded() {
        let source = track("Mrs. Robinson", ["Simon & Garfunkel"])
        XCTAssertEqual(confidence(source, SongCandidate(title: "Mrs Robinson", artist: "Simon and Garfunkel")), .high)
        let beatles = track("Let It Be", ["The Beatles"])
        XCTAssertEqual(confidence(beatles, SongCandidate(title: "Let It Be", artist: "Beatles")), .high)
    }

    func testSameISRCIsTheSameRecording() {
        let source = track("Something Else Entirely", ["Nobody"], isrc: "gb-uM7-11-00015")
        let candidate = SongCandidate(title: "Bohemian Rhapsody", artist: "Queen", isrc: "GBUM71100015")
        XCTAssertEqual(SongMatcher.score(source, candidate), 1)
    }

    func testNonLatinTitles() {
        let source = track("夜に駆ける", ["YOASOBI"], duration: 261)
        XCTAssertEqual(confidence(source, SongCandidate(title: "夜に駆ける", artist: "YOASOBI", duration: 261)), .high)
        XCTAssertNil(SongMatcher.score(source, SongCandidate(title: "群青", artist: "YOASOBI")))
    }

    // MARK: - Different songs

    func testSameTitleDifferentArtistIsNoMatch() {
        let source = track("Hurt", ["Johnny Cash"])
        XCTAssertNil(SongMatcher.score(source, SongCandidate(title: "Hurt", artist: "Nine Inch Nails")))
    }

    func testDifferentTitleIsNoMatch() {
        let source = track("Yesterday", ["The Beatles"])
        XCTAssertNil(SongMatcher.score(source, SongCandidate(title: "Help!", artist: "The Beatles")))
    }

    func testSimilarArtistNameIsNotTheArtist() {
        let source = track("Go With the Flow", ["Queen"])
        XCTAssertNil(SongMatcher.score(source, SongCandidate(title: "Go With the Flow", artist: "Queens of the Stone Age")).flatMap { $0 >= 0.9 ? $0 : nil })
    }

    // MARK: - Versions and lengths

    func testLiveVersionIsOnlyACloseMatch() {
        let source = track("Hotel California - 2013 Remaster", ["Eagles"], duration: 391)
        let live = SongCandidate(title: "Hotel California (Live)", artist: "Eagles", duration: 430)
        let studio = SongCandidate(title: "Hotel California", artist: "Eagles", duration: 390)
        XCTAssertEqual(confidence(source, live), .low)
        XCTAssertEqual(confidence(source, studio), .high)

        let ranked = SongMatcher.rank(source, among: [live, studio]) { $0 }
        XCTAssertEqual(ranked.first?.item, studio)
    }

    func testLiveAgainstLiveMatches() {
        let source = track("Hotel California - Live", ["Eagles"])
        XCTAssertEqual(confidence(source, SongCandidate(title: "Hotel California (Live)", artist: "Eagles")), .high)
    }

    func testInstrumentalIsNotOffered() {
        let source = track("Clocks", ["Coldplay"])
        let instrumental = SongCandidate(title: "Clocks (Instrumental)", artist: "Coldplay")
        XCTAssertLessThan(SongMatcher.score(source, instrumental) ?? 0, 0.75)
    }

    func testRemixWithoutLengthIsMedium() {
        let source = track("Levitating", ["Dua Lipa"])
        XCTAssertEqual(confidence(source, SongCandidate(title: "Levitating (Remix)", artist: "Dua Lipa")), .medium)
    }

    func testLengthsFarApartLowerTheScore() {
        let source = track("Blue Monday", ["New Order"], duration: 449)
        let edit = SongCandidate(title: "Blue Monday", artist: "New Order", duration: 238)
        XCTAssertLessThan(SongMatcher.score(source, edit) ?? 1, 0.75)
        XCTAssertNotNil(SongMatcher.score(source, edit))
    }

    func testAnotherEditIsWorthChecking() {
        let source = track("Eaters", ["Young Stoner Life", "Young Thug", "Travis Scott"], duration: 223)
        let album = SongCandidate(title: "Eaters (feat. Tezzus, Travis Scott & Future)", artist: "Young Stoner Life & Young Thug", duration: 261)
        XCTAssertEqual(confidence(source, album), .medium)
    }

    func testUnknownLengthCostsNothing() {
        let source = track("Blue Monday", ["New Order"])
        XCTAssertEqual(SongMatcher.score(source, SongCandidate(title: "Blue Monday", artist: "New Order", duration: 0)), 1)
    }

    func testVariousArtistsIsJudgedOnTheRest() {
        let source = track("Take On Me", ["a-ha"], duration: 225)
        let compilation = SongCandidate(title: "Take On Me", artist: "Various Artists", duration: 226)
        XCTAssertEqual(confidence(source, compilation), .medium)
    }

    func testSameAlbumBreaksTies() {
        let source = track("Yesterday", ["The Beatles"], album: "Help! (Remastered)")
        let onAlbum = SongCandidate(title: "Yesterday", artist: "The Beatles", album: "Help!")
        let onCompilation = SongCandidate(title: "Yesterday", artist: "The Beatles", album: "1")
        let ranked = SongMatcher.rank(source, among: [onCompilation, onAlbum]) { $0 }
        XCTAssertEqual(ranked.first?.item, onAlbum)
    }

    // MARK: - Search terms

    func testSearchTermDropsDecorations() {
        XCTAssertEqual(SongMatcher.searchTerm(for: track("Bohemian Rhapsody - Remastered 2011", ["Queen"])), "Bohemian Rhapsody Queen")
        XCTAssertEqual(SongMatcher.searchTerm(for: track("Hotel California - Live", ["Eagles"])), "Hotel California live Eagles")
        XCTAssertEqual(SongMatcher.searchTerm(for: track("SICKO MODE (feat. Drake)", ["Travis Scott", "Drake"])), "SICKO MODE Travis Scott")
        XCTAssertEqual(SongMatcher.searchTerm(for: track("Let's Groove", ["Earth, Wind & Fire"])), "Let's Groove Earth, Wind & Fire")
        XCTAssertEqual(SongMatcher.searchTerm(for: track("Stay", ["Rihanna feat. Mikky Ekko"])), "Stay Rihanna")
        XCTAssertEqual(SongMatcher.searchTerm(for: track("Yesterday", ["The Beatles"]), includingArtist: false), "Yesterday")
    }

    // MARK: - Index

    func testIndexFindsByTitleAndByArtist() {
        let library = [
            SongCandidate(title: "Bohemian Rhapsody", artist: "Queen", duration: 355),
            SongCandidate(title: "Dont Stop Me Now", artist: "Queen", duration: 209),
            SongCandidate(title: "Hurt", artist: "Nine Inch Nails"),
            SongCandidate(title: "Hurt", artist: "Johnny Cash"),
            SongCandidate(title: "Bohemian Rhapsody", artist: "Panic! At The Disco"),
        ]
        let index = SongIndex(library) { $0 }

        XCTAssertEqual(index.matches(for: track("Bohemian Rhapsody - Remastered 2011", ["Queen"], duration: 354)).first?.item, library[0])
        XCTAssertEqual(index.matches(for: track("Hurt", ["Johnny Cash"])).map(\.item), [library[3]])
        // Reached through the artist, the title spelt differently.
        XCTAssertEqual(index.matches(for: track("Don’t Stop Me Now - Remastered 2011", ["Queen"])).first?.item, library[1])
        XCTAssertTrue(index.matches(for: track("Killer Queen", ["Queen"])).allSatisfy { $0.confidence < .medium })
    }

    func testDiceIsSymmetricAndBounded() {
        XCTAssertEqual(SongMatcher.dice("night", "nacht"), 0.25, accuracy: 0.001)
        XCTAssertEqual(SongMatcher.dice("abc", "abc"), 1)
        XCTAssertEqual(SongMatcher.dice("a", "b"), 0)
        XCTAssertEqual(SongMatcher.dice("hello world", "world hello"), SongMatcher.dice("world hello", "hello world"))
    }
}
