@testable import MusicSearchKit
import XCTest

final class AudiobookshelfUnsentListeningTests: XCTestCase {
    override func setUp() {
        AudiobookshelfAPI.forgetUnsentListening()
    }

    override func tearDown() {
        AudiobookshelfAPI.forgetUnsentListening()
    }

    func testListeningAddsUpABookADay() throws {
        let morning = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 9)))
        AudiobookshelfAPI.noteUnsentListening(itemID: "li_1", currentTime: 115, timeListened: 15, duration: 3600, at: morning)
        AudiobookshelfAPI.noteUnsentListening(itemID: "li_1", currentTime: 130, timeListened: 15, duration: 3600, at: morning.addingTimeInterval(15))
        AudiobookshelfAPI.noteUnsentListening(itemID: "li_2~ep_1", currentTime: 30, timeListened: 30, duration: 1800, at: morning.addingTimeInterval(60))
        // Nothing heard is nothing to tell.
        AudiobookshelfAPI.noteUnsentListening(itemID: "li_3", currentTime: 0, timeListened: 0, duration: 100, at: morning)
        // The next day is a session of its own.
        AudiobookshelfAPI.noteUnsentListening(itemID: "li_1", currentTime: 145, timeListened: 15, duration: 3600, at: morning.addingTimeInterval(86_400))

        let pending = AudiobookshelfAPI.pendingUnsentListening()
        XCTAssertEqual(pending.map(\.itemID), ["li_1", "li_2~ep_1", "li_1"])
        let first = try XCTUnwrap(pending.first)
        XCTAssertEqual(first.timeListening, 30)
        XCTAssertEqual(first.startTime, 100)
        XCTAssertEqual(first.currentTime, 130)
        XCTAssertEqual(first.date, "2026-10-27")
        XCTAssertEqual(first.dayOfWeek, "Tuesday")
        XCTAssertEqual(pending.last?.date, "2026-10-28")
    }

    func testLocalSessionBodyNamesTheEpisode() throws {
        let morning = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 9)))
        AudiobookshelfAPI.noteUnsentListening(itemID: "li_2~ep_1", currentTime: 30, timeListened: 30, duration: 1800, at: morning)
        let session = try XCTUnwrap(AudiobookshelfAPI.pendingUnsentListening().first)
        let body = AudiobookshelfAPI.body(of: session)
        XCTAssertEqual(body["libraryItemId"] as? String, "li_2")
        XCTAssertEqual(body["episodeId"] as? String, "ep_1")
        XCTAssertEqual(body["mediaType"] as? String, "podcast")
        XCTAssertEqual(body["playMethod"] as? Int, 3)
        XCTAssertEqual(body["timeListening"] as? Double, 30)
    }
}
