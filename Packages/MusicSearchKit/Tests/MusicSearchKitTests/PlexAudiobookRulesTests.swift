@testable import MusicSearchKit
import XCTest

final class PlexAudiobookRulesTests: XCTestCase {
    func testLibraryNamesThatMeanBooks() {
        for title in ["Audiobooks", "Books", "Kids' Audiobooks", "Hörbücher", "Livres audio", "Audiolibros", "Luisterboeken"] {
            XCTAssertTrue(PlexAudiobookRules.looksLikeAudiobooks(title: title, agent: nil), title)
        }
        for title in ["Music", "Classical", "Soundtracks", "Podcasts"] {
            XCTAssertFalse(PlexAudiobookRules.looksLikeAudiobooks(title: title, agent: nil), title)
        }
    }

    func testABookAgentMeansBooksWhateverTheName() {
        XCTAssertTrue(PlexAudiobookRules.looksLikeAudiobooks(title: "Listening", agent: "com.plexapp.agents.audnexus"))
        XCTAssertFalse(PlexAudiobookRules.looksLikeAudiobooks(title: "Music", agent: "tv.plex.agents.music"))
    }

    func testAudiobookGenres() {
        XCTAssertTrue(PlexAudiobookRules.isAudiobookGenre("Audiobook"))
        XCTAssertTrue(PlexAudiobookRules.isAudiobookGenre(" audiobooks "))
        // Comedy, poetry and speeches in a music library, not books.
        XCTAssertFalse(PlexAudiobookRules.isAudiobookGenre("Spoken Word"))
        XCTAssertTrue(PlexAudiobookRules.isAudiobookGenre("Horbuch"))
        XCTAssertFalse(PlexAudiobookRules.isAudiobookGenre("Rock"))
        XCTAssertFalse(PlexAudiobookRules.isAudiobookGenre("Books & Spoken"))
    }
}
