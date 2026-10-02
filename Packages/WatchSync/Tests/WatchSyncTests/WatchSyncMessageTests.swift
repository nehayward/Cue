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

    func testTheiPhonesContextCarriesTheLibraryAndSignIns() throws {
        var library = library(albums: 3, tracksEach: 12)
        library.quality = .small
        let credentials = WatchCredentials(
            plex: .init(token: "tok", serverID: "srv", librarySectionID: "3", connectionPreference: "auto"),
            subsonic: .init(serverAddress: "https://music.example", username: "me", password: "pw")
        )
        let (context, fits) = try WatchSyncMessage.context(library: library, credentials: credentials, sentAt: Date(timeIntervalSince1970: 5))
        XCTAssertTrue(fits)
        XCTAssertEqual(WatchSyncMessage.library(in: context), library)
        XCTAssertEqual(WatchSyncMessage.library(in: context)?.quality, .small)
        XCTAssertEqual(WatchSyncMessage.credentials(in: context), credentials)
        XCTAssertNil(WatchSyncMessage.status(in: context))
        XCTAssertEqual(WatchSyncMessage.revision(in: context), library.revision)
        XCTAssertNil(WatchSyncMessage.library(in: [:]))
        XCTAssertNil(WatchSyncMessage.library(in: [WatchSyncMessage.libraryKey: Data([9, 9])]))
    }

    func testTheWatchsContextCarriesTheLibraryAndStatus() throws {
        let library = library(albums: 1, tracksEach: 3)
        let status = WatchStatus(library: library, isDownloaded: { _ in false }, pendingCount: 3, failedCount: 0, bytesUsed: 0, updatedAt: .now)
        let (context, _) = try WatchSyncMessage.context(library: library, status: status)
        XCTAssertEqual(WatchSyncMessage.library(in: context), library)
        XCTAssertEqual(WatchSyncMessage.status(in: context), status)
        XCTAssertNil(WatchSyncMessage.credentials(in: context))
    }

    func testSendingAgainChangesTheContext() throws {
        let library = library(albums: 1, tracksEach: 2)
        let first = try WatchSyncMessage.context(library: library, sentAt: Date(timeIntervalSince1970: 1)).context
        let second = try WatchSyncMessage.context(library: library, sentAt: Date(timeIntervalSince1970: 2)).context
        XCTAssertNotEqual(first[WatchSyncMessage.sentAtKey] as? Double, second[WatchSyncMessage.sentAtKey] as? Double)
    }

    func testATooBigLibraryIsLeftOutForAFile() throws {
        // Unpacked here (Linux has no LZFSE), so a few hundred songs is over.
        let big = library(albums: 40, tracksEach: 12)
        let packed = WatchSyncMessage.pack(try big.encoded())
        let (context, fits) = try WatchSyncMessage.context(library: big, credentials: WatchCredentials())
        XCTAssertEqual(fits, packed.count <= WatchSyncMessage.contextLimit)
        XCTAssertEqual(WatchSyncMessage.library(in: context) != nil, fits)
        XCTAssertNotNil(WatchSyncMessage.credentials(in: context))
        XCTAssertEqual(try WatchLibrary.decoded(from: XCTUnwrap(WatchSyncMessage.unpack(packed))), big)
    }

    func testALibraryFromBeforeQualityAndOriginsStillReads() throws {
        let old = """
        {"revision":5,"collections":[{"key":"album-1","kind":"album","title":"A","subtitle":"","addedAt":0,"trackKeys":["1"]}],
         "tracks":{"1":{"key":"1","title":"S","artist":"X","streamURL":"https://s.example/1","fileExtension":"flac"}}}
        """
        let library = try WatchLibrary.decoded(from: Data(old.utf8))
        XCTAssertNil(library.quality)
        XCTAssertEqual(library.effectiveQuality, .recommended)
        XCTAssertNil(library.tracks["1"]?.origin)
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
        let context = try WatchSyncMessage.context(library: nil, status: status).context
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
        let data = try XCTUnwrap(WatchSyncMessage.context(library: nil, status: status).context[WatchSyncMessage.statusKey] as? Data)
        XCTAssertEqual(status.downloadedCount, 2_000)
        XCTAssertLessThan(data.count, 16_000)
    }
}
