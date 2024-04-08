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

        let spotifySearch = try XCTUnwrap(decoder.decode(SpotifyResult.self, from: Data(contentsOf: duaLipa)))
        let playlists = try XCTUnwrap(spotifySearch.playlists)
        XCTAssertEqual(playlists.items.count, 20)
    }

}
