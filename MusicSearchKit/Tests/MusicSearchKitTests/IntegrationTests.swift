import XCTest
import MusicSearchKit

final class IntegrationsTests: XCTestCase {
    let musicSearchService = MusicSearchService()

    func testSpotifySearch() async throws {
        let results = await musicSearchService.searchSpotify(song: "", artist: "Dua Lipa")
        XCTAssertNotNil(results, "Results is nil")
    }
}
