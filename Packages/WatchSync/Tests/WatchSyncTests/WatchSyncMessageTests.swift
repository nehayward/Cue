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

    private func library(albums: Int, tracksEach: Int) -> WatchLibrary {
        var library = WatchLibrary.empty
        for album in 0 ..< albums {
            let keys = (0 ..< tracksEach).map { "subsonic-al\(album)-tr\($0)" }
            let tracks = keys.map {
                WatchTrack(
                    key: $0,
                    title: "Song \($0)",
                    artist: "Artist",
                    album: "Album \(album)",
                    artworkURL: URL(string: "https://music.example/rest/getCoverArt?id=al\(album)&u=me&t=0123456789abcdef&s=salt&v=1.16.1&c=Cue"),
                    streamURL: URL(string: "https://music.example/rest/stream?id=\($0)&u=me&t=0123456789abcdef&s=salt&v=1.16.1&c=Cue&format=mp3&maxBitRate=256")!,
                    fileExtension: "mp3",
                    duration: 215
                )
            }
            library.upsert(WatchCollection(key: "album-al\(album)", kind: .album, title: "Album \(album)", subtitle: "Artist", addedAt: .now, trackKeys: keys), tracks: tracks)
        }
        library.bumpRevision(now: Date(timeIntervalSince1970: 100))
        return library
    }

    func testALibraryRoundTripsThroughApplicationContext() throws {
        let library = library(albums: 3, tracksEach: 12)
        let context = try XCTUnwrap(WatchSyncMessage.libraryContext(library, sentAt: Date(timeIntervalSince1970: 5)))
        XCTAssertEqual(WatchSyncMessage.library(in: context), library)
        XCTAssertEqual(WatchSyncMessage.revision(in: context), library.revision)
        XCTAssertTrue(WatchSyncMessage.isLibrary(context))
        XCTAssertNil(WatchSyncMessage.library(in: [:]))
        XCTAssertNil(WatchSyncMessage.library(in: [WatchSyncMessage.libraryKey: Data([9, 9])]))
    }

    func testSendingAgainChangesTheContext() throws {
        let library = library(albums: 1, tracksEach: 2)
        let first = try XCTUnwrap(WatchSyncMessage.libraryContext(library, sentAt: Date(timeIntervalSince1970: 1)))
        let second = try XCTUnwrap(WatchSyncMessage.libraryContext(library, sentAt: Date(timeIntervalSince1970: 2)))
        XCTAssertNotEqual(first[WatchSyncMessage.sentAtKey] as? Double, second[WatchSyncMessage.sentAtKey] as? Double)
    }

    func testATooBigLibraryGoesAsAFile() throws {
        // Unpacked here (Linux has no LZFSE), so a few hundred songs is over.
        let big = library(albums: 40, tracksEach: 12)
        let packed = WatchSyncMessage.pack(try big.encoded())
        if packed.count > WatchSyncMessage.contextLimit {
            XCTAssertNil(try WatchSyncMessage.libraryContext(big))
        } else {
            XCTAssertNotNil(try WatchSyncMessage.libraryContext(big))
        }
        XCTAssertEqual(try WatchLibrary.decoded(from: XCTUnwrap(WatchSyncMessage.unpack(packed))), big)
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
