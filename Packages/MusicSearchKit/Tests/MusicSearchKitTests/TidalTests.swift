import XCTest
import MusicSearchKit

final class TidalTests: XCTestCase {
    let tidal = TidalAPI()

    func testTidalSearch() async throws{
        let result = await tidal.search(for: "Du")
        print(result)
    }

    func testAlbumTracks() async throws{
        let result = await tidal.albumSongs(id: "360212374")
        print(result)
    }
}
