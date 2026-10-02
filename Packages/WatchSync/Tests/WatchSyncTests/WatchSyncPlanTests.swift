import XCTest
@testable import WatchSync

final class WatchSyncPlanTests: XCTestCase {
    private func library(_ collections: [(String, [String])]) -> WatchLibrary {
        var library = WatchLibrary.empty
        for (key, trackKeys) in collections.reversed() {
            let tracks = trackKeys.map {
                WatchTrack(key: $0, title: $0, artist: "", streamURL: URL(string: "https://s.example/\($0)")!, fileExtension: "mp3")
            }
            library.upsert(WatchCollection(key: key, kind: .playlist, title: key, subtitle: "", addedAt: .now, trackKeys: trackKeys), tracks: tracks)
        }
        return library
    }

    func testFetchesWhatsMissingInLibraryOrderAndDeletesWhatsGone() {
        let plan = WatchSyncPlan.make(
            library: library([("new", ["4", "1"]), ("old", ["1", "2"])]),
            present: ["2", "3", "9"]
        )
        XCTAssertEqual(plan.toDownload, ["4", "1"])
        XCTAssertEqual(plan.toRemove, ["3", "9"])
    }

    func testAnEmptyLibraryDeletesEverything() {
        let plan = WatchSyncPlan.make(library: .empty, present: ["b", "a"])
        XCTAssertEqual(plan.toDownload, [])
        XCTAssertEqual(plan.toRemove, ["a", "b"])
    }

    func testNothingToDoWhenTheWatchMatches() {
        let plan = WatchSyncPlan.make(library: library([("a", ["1", "2"])]), present: ["1", "2"])
        XCTAssertTrue(plan.isEmpty)
    }
}
