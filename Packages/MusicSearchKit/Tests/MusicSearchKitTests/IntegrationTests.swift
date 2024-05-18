import XCTest
import MusicSearchKit

final class IntegrationsTests: XCTestCase {
    let plexAPI = PlexAPI()

    func testSearchPlex() async throws{
        await plexAPI.search(for: "Dua")
    }

    func testSearchPlexDance() async throws{
        let results = await plexAPI.search(for: "Dance")
        print(results)
    }

    func testSearchPlexHarry() async throws{
        let results = await plexAPI.search(for: "Harry")
        print(results)
    }
//    func testSpotifySearch() async throws {
//        let results = await  searchSpotify(song: "", artist: "Dua Lipa")
//        XCTAssertNotNil(results, "Results is nil")
//    }
//
//    func testSpotifyTrackLookup() async throws {
//        let results = await musicSearchService.spotifyTrackLookup(id: "4LihUZcWy0B6lGLqcJ8u9B")
//        XCTAssertNotNil(results, "Results is nil")
//    }
//
//    func testSpotifyAlbumTrackLookup() async throws {
//        let results = await musicSearchService.spotifyAlbumTracksLookup(id: "6PeoltoiWQWCyWA0JBHVGN")
//        let results2 = await musicSearchService.spotifyAlbumTracksLookup(id: "6BzxX6zkDsYKFJ04ziU5xQ")
//
//        XCTAssertNotNil(results, "Results is nil")
//    }
//
//    func testAppleSearch() async throws {
//        let results = await musicSearchService.search(song: "", artist: "Dua Lipa")
//        XCTAssertNotNil(results, "Results is nil")
//    }
//
//    func testAppleLookup() async throws {
//        let results = await musicSearchService.appleLookup(id: "1590036028")
//        XCTAssertNotNil(results, "Results is nil")
//    }
}
