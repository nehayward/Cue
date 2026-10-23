@testable import MusicSearchKit
import XCTest

final class AudiobookshelfTests: XCTestCase {
    // MARK: Addresses

    func testNormalizedAddress() {
        XCTAssertEqual(AudiobookshelfURLs.normalizedAddress("nas.local:13378"), "http://nas.local:13378")
        XCTAssertEqual(AudiobookshelfURLs.normalizedAddress(" https://abs.example.com/ "), "https://abs.example.com")
        // The web client's pages go; a proxy's subpath stays.
        XCTAssertEqual(AudiobookshelfURLs.normalizedAddress("https://abs.example.com/library/abc/bookshelf"), "https://abs.example.com")
        XCTAssertEqual(AudiobookshelfURLs.normalizedAddress("https://example.com/audiobookshelf/login?redirect=%2F"), "https://example.com/audiobookshelf")
        XCTAssertEqual(AudiobookshelfURLs.normalizedAddress("https://user:pw@example.com/abs/item/123#top"), "https://example.com/abs")
        XCTAssertNil(AudiobookshelfURLs.normalizedAddress("   "))
    }

    func testTrackAndFileURLs() throws {
        let base = try XCTUnwrap(URL(string: "https://example.com/abs"))
        XCTAssertEqual(
            AudiobookshelfURLs.sessionTrackURL(base: base, sessionID: "s1", index: 2, fileExtension: "m4b")?.absoluteString,
            "https://example.com/abs/public/session/s1/track/2?ext=.m4a"
        )
        XCTAssertEqual(
            AudiobookshelfURLs.fileURL(base: base, itemID: "li_1", fileID: "123", token: "t0k", fileExtension: "mp3")?.absoluteString,
            "https://example.com/abs/api/items/li_1/file/123?token=t0k&ext=.mp3"
        )
        XCTAssertEqual(
            AudiobookshelfURLs.coverURL(base: base, itemID: "li_1", width: 600)?.absoluteString,
            "https://example.com/abs/api/items/li_1/cover?format=jpeg&width=600"
        )
    }

    func testPartIDsRoundTrip() {
        let id = AudiobookshelfPartID(itemID: "li_8f2", index: 3, fileID: "649644248522215260")
        XCTAssertEqual(AudiobookshelfPartID(id.string), id)
        XCTAssertNil(AudiobookshelfPartID("li_8f2|x|1"))
        XCTAssertNil(AudiobookshelfPartID("li_8f2"))
    }

    func testPartReadBackFromASpeakersURL() {
        let sessions = ["ps_9": "li_1"]
        let fromSession = AudiobookshelfURLs.partID(
            fromStreamURL: "https://example.com/abs/public/session/ps_9/track/2?ext=.m4a",
            itemForSession: { sessions[$0] }
        )
        XCTAssertEqual(fromSession, AudiobookshelfPartID(itemID: "li_1", index: 2, fileID: "-"))
        let fromFile = AudiobookshelfURLs.partID(
            fromStreamURL: "http://nas:13378/api/items/li_1/file/222?token=x&ext=.m4a",
            itemForSession: { _ in nil }
        )
        XCTAssertEqual(fromFile, AudiobookshelfPartID(itemID: "li_1", index: 0, fileID: "222"))
        XCTAssertNil(AudiobookshelfURLs.partID(fromStreamURL: "https://example.com/public/session/gone/track/1", itemForSession: { _ in nil }))
        XCTAssertTrue(AudiobookshelfURLs.isStreamURL("https://example.com/abs/public/session/ps_9/track/2"))
        XCTAssertFalse(AudiobookshelfURLs.isStreamURL("http://nas:4533/rest/stream?id=1"))

        let part = AudiobookshelfPartID(itemID: "li_1", index: 2, fileID: "222")
        XCTAssertTrue(part.isSameFile(as: fromSession!))
        XCTAssertTrue(part.isSameFile(as: fromFile!))
        XCTAssertFalse(part.isSameFile(as: AudiobookshelfPartID(itemID: "li_1", index: 1, fileID: "-")))
        XCTAssertFalse(part.isSameFile(as: AudiobookshelfPartID(itemID: "li_2", index: 2, fileID: "222")))
    }

    // MARK: JSON

    private let expandedItem = """
    {"id": "li_1", "libraryId": "lib_1", "mediaType": "book", "addedAt": 1700000000000,
     "media": {"duration": 3600.5, "numTracks": 2, "numChapters": 3,
       "metadata": {"title": "The Hobbit", "authorName": "J. R. R. Tolkien", "narratorName": "Andy Serkis",
                    "seriesName": null, "description": "In a hole in the ground…", "publishedYear": "2020"},
       "chapters": [{"id": 0, "start": 0, "end": 1200, "title": "An Unexpected Party"},
                    {"id": 1, "start": 1200, "end": 2400, "title": "Roast Mutton"},
                    {"id": 2, "start": 2400, "end": 3600.5, "title": "A Short Rest"}],
       "tracks": [{"index": 1, "startOffset": 0, "duration": 1800, "title": "01.m4b",
                   "contentUrl": "/api/items/li_1/file/111", "mimeType": "audio/mp4",
                   "metadata": {"filename": "01.m4b", "ext": ".m4b"}},
                  {"index": 2, "startOffset": 1800, "duration": 1800.5, "title": "02.m4b",
                   "contentUrl": "/api/items/li_1/file/222", "mimeType": "audio/mp4", "ino": "222",
                   "metadata": {"filename": "02.m4b", "ext": ".m4b"}}]},
     "userMediaProgress": {"libraryItemId": "li_1", "currentTime": 2000, "duration": 3600.5,
                           "progress": 0.55, "isFinished": false, "lastUpdate": 1700000500000}}
    """

    func testExpandedItem() throws {
        let item = try JSONDecoder().decode(AudiobookshelfItem.self, from: Data(expandedItem.utf8))
        XCTAssertTrue(item.hasAudio)
        XCTAssertEqual(item.media?.metadata?.narratorName, "Andy Serkis")
        XCTAssertEqual(item.timeline.partDurations, [1800, 1800.5])
        XCTAssertEqual(item.chapters.map(\.title), ["An Unexpected Party", "Roast Mutton", "A Short Rest"])
        let tracks = try XCTUnwrap(item.media?.tracks)
        XCTAssertEqual(tracks.map(\.fileID), ["111", "222"])
        XCTAssertEqual(tracks.map(\.fileExtension), ["m4b", "m4b"])
        let progress = try XCTUnwrap(item.progress)
        XCTAssertEqual(progress.position, 2000)
        XCTAssertEqual(progress.updatedAt, Date(timeIntervalSince1970: 1_700_000_500))
    }

    func testMinifiedPageAndEbooks() throws {
        let json = """
        {"results": [
          {"id": "li_1", "mediaType": "book", "media": {"duration": 100, "numTracks": 1, "metadata": {"title": "Audio"}}},
          {"id": "li_2", "mediaType": "book", "media": {"duration": 0, "numTracks": 0, "metadata": {"title": "Ebook only"}}}
        ], "total": 2, "limit": 50, "page": 0}
        """
        let page = try JSONDecoder().decode(AudiobookshelfItemsPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.total, 2)
        XCTAssertEqual(page.results.filter(\.hasAudio).map(\.id), ["li_1"])
    }

    func testABookOfFilesWithoutMarksHasAChapterAFile() throws {
        let json = """
        {"id": "li_3", "media": {"duration": 90, "tracks": [
          {"index": 1, "duration": 30, "title": "Chapter 1"}, {"index": 2, "duration": 60, "title": "Chapter 2"}]}}
        """
        let item = try JSONDecoder().decode(AudiobookshelfItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.chapters.map(\.title), ["Chapter 1", "Chapter 2"])
        XCTAssertEqual(item.chapters.map(\.start), [0, 30])
    }

    func testLoginAndSession() throws {
        let login = """
        {"user": {"id": "u1", "username": "nick", "token": "legacy", "accessToken": "access", "refreshToken": "refresh",
                  "mediaProgress": [], "type": "user"}, "userDefaultLibraryId": "lib_1", "serverSettings": {}}
        """
        let response = try JSONDecoder().decode(AudiobookshelfLoginResponse.self, from: Data(login.utf8))
        XCTAssertEqual(response.user.accessToken, "access")
        XCTAssertEqual(response.user.refreshToken, "refresh")
        XCTAssertEqual(response.userDefaultLibraryId, "lib_1")

        let session = """
        {"id": "ps_1", "libraryItemId": "li_1", "currentTime": 12.5, "duration": 3600, "playMethod": 0,
         "audioTracks": [{"index": 1, "startOffset": 0, "duration": 3600, "contentUrl": "/api/items/li_1/file/9", "mimeType": "audio/mp4"}],
         "chapters": []}
        """
        let decoded = try JSONDecoder().decode(AudiobookshelfSession.self, from: Data(session.utf8))
        XCTAssertEqual(decoded.audioTracks?.first?.fileID, "9")
        XCTAssertEqual(decoded.currentTime, 12.5)
    }
}
