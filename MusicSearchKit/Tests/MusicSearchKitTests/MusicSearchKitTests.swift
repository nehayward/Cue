import XCTest
@testable import MusicSearchKit

final class MusicSearchKitTests: XCTestCase {
    func testSearchForCryYourHeartOutSong() throws {
        let cryYourHeartOutQueryURL = Bundle.module.url(forResource: "cryYourHeartOutSearch", withExtension: "json")!
        let musicSearch = try JSONDecoder().decode(ItunesMusicSearch.self, from: Data(contentsOf: cryYourHeartOutQueryURL))
        XCTAssertEqual(musicSearch.results.count, 50)
        XCTAssertEqual(musicSearch.results.first?.trackName, "Cry Your Heart Out")
    }
    
}
