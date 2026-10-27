import XCTest
@testable import WatchSync

final class WatchAllowanceTests: XCTestCase {
    func testNoLimitAdmitsEverything() {
        let admitted = WatchAllowance.unlimited.admitted(["a", "b", "book1"], kept: [], bookFiles: ["book1"])
        XCTAssertEqual(admitted, ["a", "b", "book1"])
    }

    func testTheShareGoesInOrder() {
        let allowance = WatchAllowance(songs: 2, allowsBooks: true)
        XCTAssertEqual(allowance.admitted(["a", "b", "c", "d"], kept: [], bookFiles: []), ["a", "b"])
    }

    func testWhatsKeptStaysAndTakesItsShareFirst() {
        let allowance = WatchAllowance(songs: 2, allowsBooks: true)
        // "c" is on the watch already: it stays, and leaves room for one more.
        XCTAssertEqual(allowance.admitted(["a", "b", "c"], kept: ["c"], bookFiles: []), ["a", "c"])
    }

    func testOverTheShareNothingKeptIsLost() {
        let allowance = WatchAllowance(songs: 1, allowsBooks: true)
        XCTAssertEqual(allowance.admitted(["a", "b", "c"], kept: ["b", "c"], bookFiles: []), ["b", "c"])
    }

    func testANoneShareAdmitsOnlyWhatsKept() {
        let allowance = WatchAllowance(songs: 0, allowsBooks: true)
        XCTAssertEqual(allowance.admitted(["a", "b"], kept: ["b"], bookFiles: []), ["b"])
    }

    func testBooksWaitWithoutSuperButKeepWhatsHere() {
        let allowance = WatchAllowance(songs: 50, allowsBooks: false)
        let admitted = allowance.admitted(["a", "book1", "book2"], kept: ["book2"], bookFiles: ["book1", "book2"])
        XCTAssertEqual(admitted, ["a", "book2"])
    }

    func testBooksDontUseTheSongsShare() {
        let allowance = WatchAllowance(songs: 1, allowsBooks: true)
        let admitted = allowance.admitted(["book1", "book2", "a", "b"], kept: ["book1"], bookFiles: ["book1", "book2"])
        XCTAssertEqual(admitted, ["book1", "book2", "a"])
    }

    func testASongWantedTwiceTakesOneSlot() {
        let allowance = WatchAllowance(songs: 2, allowsBooks: true)
        XCTAssertEqual(allowance.admitted(["a", "a", "b"], kept: [], bookFiles: []), ["a", "b"])
    }

    func testTheShareAndWhatsHeldCross() throws {
        let allowance = WatchAllowance(songs: 12, allowsBooks: false)
        let held = WatchHeldDownloads(songs: 30, books: 2)
        let context = try WatchSyncMessage.context(picks: .empty, allowance: allowance, held: held)
        XCTAssertEqual(WatchSyncMessage.allowance(in: context), allowance)
        XCTAssertEqual(WatchSyncMessage.held(in: context), held)
        XCTAssertEqual(held.total, 32)
    }

    func testAContextWithoutThemHasNeither() throws {
        let context = try WatchSyncMessage.context(picks: .empty)
        XCTAssertNil(WatchSyncMessage.allowance(in: context))
        XCTAssertNil(WatchSyncMessage.held(in: context))
    }
}
