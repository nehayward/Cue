import XCTest
@testable import WatchSync

final class WatchSyncMessageTests: XCTestCase {
    func testLibraryMetadataNamesTheFileAndItsRevision() {
        let metadata = WatchSyncMessage.libraryMetadata(revision: 42)
        XCTAssertTrue(WatchSyncMessage.isLibrary(metadata))
        XCTAssertEqual(WatchSyncMessage.revision(in: metadata), 42)
        XCTAssertFalse(WatchSyncMessage.isLibrary(["kind": "other"]))
        XCTAssertFalse(WatchSyncMessage.isLibrary(nil))
    }

    func testRevisionReadsANumberOfAnotherWidth() {
        let metadata: [String: Any] = [WatchSyncMessage.revisionKey: NSNumber(value: Int64(1_759_000_000_000))]
        XCTAssertEqual(WatchSyncMessage.revision(in: metadata), 1_759_000_000_000)
    }

    func testStatusRoundTripsThroughApplicationContext() throws {
        let status = WatchStatus(
            libraryRevision: 7,
            downloadedByCollection: ["album-1": 2],
            downloadedCount: 2,
            pendingCount: 3,
            failedCount: 1,
            bytesUsed: 12_345,
            updatedAt: Date(timeIntervalSince1970: 99)
        )
        let context = try WatchSyncMessage.statusContext(status)
        XCTAssertEqual(WatchSyncMessage.status(in: context), status)
        XCTAssertNil(WatchSyncMessage.status(in: [:]))
    }

    func testStatusCountsEachCollectionAndEachSongOnce() {
        func track(_ key: String) -> WatchTrack {
            WatchTrack(key: key, title: key, artist: "", streamURL: URL(string: "https://s.example/\(key)")!, fileExtension: "mp3")
        }
        var library = WatchLibrary.empty
        library.upsert(WatchCollection(key: "a", kind: .album, title: "A", subtitle: "", addedAt: .now, trackKeys: ["1", "2", "3"]), tracks: [track("1"), track("2"), track("3")])
        library.upsert(WatchCollection(key: "b", kind: .playlist, title: "B", subtitle: "", addedAt: .now, trackKeys: ["3", "4"]), tracks: [track("3"), track("4")])
        library.bumpRevision(now: Date(timeIntervalSince1970: 1))

        let here: Set<String> = ["1", "3"]
        let status = WatchStatus(library: library, isDownloaded: here.contains, pendingCount: 2, failedCount: 0, bytesUsed: 10, updatedAt: .now)
        XCTAssertEqual(status.libraryRevision, library.revision)
        XCTAssertEqual(status.downloadedByCollection, ["a": 2, "b": 1])
        XCTAssertEqual(status.downloadedCount, 2)
    }

    func testAStatusForTwoThousandSongsStaysSmall() throws {
        var library = WatchLibrary.empty
        for album in 0 ..< 200 {
            let keys = (0 ..< 10).map { "subsonic-album\(album)-track\($0)" }
            let tracks = keys.map { WatchTrack(key: $0, title: $0, artist: "", streamURL: URL(string: "https://s.example/\($0)")!, fileExtension: "flac") }
            library.upsert(WatchCollection(key: "album-\(album)", kind: .album, title: "", subtitle: "", addedAt: .now, trackKeys: keys), tracks: tracks)
        }
        let status = WatchStatus(library: library, isDownloaded: { _ in true }, pendingCount: 0, failedCount: 0, bytesUsed: 1, updatedAt: .now)
        let data = try XCTUnwrap(WatchSyncMessage.statusContext(status)[WatchSyncMessage.statusKey] as? Data)
        XCTAssertEqual(status.downloadedCount, 2_000)
        XCTAssertLessThan(data.count, 16_000)
    }
}
