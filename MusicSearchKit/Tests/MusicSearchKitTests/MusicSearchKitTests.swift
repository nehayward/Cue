import XCTest
@testable import MusicSearchKit

final class MusicSearchKitTests: XCTestCase {
    func testSearchForCryYourHeartOutSong() throws {
        let cryYourHeartOutQueryURL = Bundle.module.url(forResource: "cryYourHeartOutSearch", withExtension: "json")!
        let musicSearch = try JSONDecoder().decode(ItunesMusicSearch.self, from: Data(contentsOf: cryYourHeartOutQueryURL))
        XCTAssertEqual(musicSearch.results.count, 50)
        XCTAssertEqual(musicSearch.results.first?.trackName, "Cry Your Heart Out")
    }

    func testSpotifyDecode() throws {
        let duaLipa = Bundle.module.url(forResource: "duaLipaSpotifyPlaylistsResponse", withExtension: "json")!
        let decoder =  JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let spotifySearch = try decoder.decode(SpotifyResult.self, from: Data(contentsOf: duaLipa))
        XCTAssertEqual(spotifySearch.playlists.items.count, 20)
//        XCTAssertEqual(musicSearch.results.first?.trackName, "Cry Your Heart Out")
    }

}
