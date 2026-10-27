@testable import MusicSearchKit
import XCTest

final class AudiobookshelfCollectionTests: XCTestCase {
    func testCollectionsPageKeepsItsBooksInOrder() throws {
        let json = """
        { "results": [
            { "id": "col_1", "libraryId": "lib_b", "name": "Summer Reading", "description": null,
              "books": [
                { "id": "li_2", "mediaType": "book", "media": { "numTracks": 1, "metadata": { "title": "Second" } } },
                { "id": "li_1", "mediaType": "book", "media": { "numTracks": 3, "metadata": { "title": "First" } } },
                { "id": "li_3", "mediaType": "book", "media": { "numTracks": 0, "metadata": { "title": "An Ebook" } } }
              ], "lastUpdate": 1700000000000, "createdAt": 1690000000000 }
        ], "total": 1, "limit": 100, "page": 0 }
        """
        let page = try JSONDecoder().decode(AudiobookshelfCollectionsPage.self, from: Data(json.utf8))
        let collection = try XCTUnwrap(page.results.first)
        XCTAssertEqual(collection.name, "Summer Reading")
        XCTAssertEqual(collection.books?.map(\.id), ["li_2", "li_1", "li_3"])
        // An ebook has nothing to listen to.
        XCTAssertEqual(collection.books?.filter(\.hasAudio).map(\.id), ["li_2", "li_1"])
    }
}
