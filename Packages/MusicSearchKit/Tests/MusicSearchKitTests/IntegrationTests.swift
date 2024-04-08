import XCTest
import MusicSearchKit

final class IntegrationsTests: XCTestCase {
    let musicSearchService = MusicSearchService()

    func testSpotifySearch() async throws {
        let results = await musicSearchService.searchSpotify(song: "", artist: "Dua Lipa")
        XCTAssertNotNil(results, "Results is nil")
    }

    func testSpotifyTrackLookup() async throws {
        let results = await musicSearchService.spotifyTrackLookup(id: "4LihUZcWy0B6lGLqcJ8u9B")
        XCTAssertNotNil(results, "Results is nil")
    }

    func testAppleSearch() async throws {
        let results = await musicSearchService.search(song: "", artist: "Dua Lipa")
        XCTAssertNotNil(results, "Results is nil")
    }

    func testAppleLookup() async throws {
        let results = await musicSearchService.appleLookup(id: "1590036028")
        XCTAssertNotNil(results, "Results is nil")
    }
}
