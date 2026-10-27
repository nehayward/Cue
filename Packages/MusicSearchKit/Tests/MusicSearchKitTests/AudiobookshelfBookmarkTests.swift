@testable import MusicSearchKit
import XCTest

final class AudiobookshelfBookmarkTests: XCTestCase {
    func testAccountCarriesBookmarks() throws {
        let json = """
        { "id": "usr_1", "username": "me",
          "mediaProgress": [ { "libraryItemId": "li_1", "currentTime": 10, "duration": 100 } ],
          "bookmarks": [
            { "libraryItemId": "li_1", "title": "The twist", "time": 3723, "createdAt": 1700000000000 },
            { "libraryItemId": "li_1", "title": "Later", "time": 4000.5, "createdAt": 1700000001000 },
            { "libraryItemId": "li_2", "title": "", "time": 12, "createdAt": 1700000002000 }
          ] }
        """
        let user = try JSONDecoder().decode(AudiobookshelfUser.self, from: Data(json.utf8))
        let byItem = Dictionary(grouping: user.bookmarks ?? [], by: \.libraryItemId)
        XCTAssertEqual(byItem["li_1"]?.map(\.title), ["The twist", "Later"])
        XCTAssertEqual(byItem["li_2"]?.first?.time, 12)
    }

    func testBookmarkTimeAsThePathNamesIt() {
        XCTAssertEqual(AudiobookshelfAPI.bookmarkTime(3723), "3723")
        XCTAssertEqual(AudiobookshelfAPI.bookmarkTime(0), "0")
        XCTAssertEqual(AudiobookshelfAPI.bookmarkTime(4000.5), "4000.5")
    }
}
