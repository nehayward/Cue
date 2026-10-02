import XCTest
@testable import WatchSync

final class WatchLibraryTests: XCTestCase {
    private func track(_ key: String) -> WatchTrack {
        WatchTrack(
            key: key,
            title: "Song \(key)",
            artist: "Artist",
            streamURL: URL(string: "https://plex.example/library/parts/\(key)/file.flac?X-Plex-Token=t")!,
            fileExtension: "flac"
        )
    }

    private func album(_ key: String, _ trackKeys: [String], at seconds: TimeInterval = 0) -> WatchCollection {
        WatchCollection(key: key, kind: .album, title: "Album \(key)", subtitle: "Artist", addedAt: Date(timeIntervalSince1970: seconds), trackKeys: trackKeys)
    }

    func testUpsertPutsTheCollectionFirstWithItsTracks() {
        var library = WatchLibrary.empty
        library.upsert(album("a", ["1", "2"]), tracks: [track("1"), track("2")])
        library.upsert(album("b", ["3"]), tracks: [track("3")])

        XCTAssertEqual(library.collections.map(\.key), ["b", "a"])
        XCTAssertEqual(Set(library.tracks.keys), ["1", "2", "3"])
        XCTAssertEqual(library.tracks(in: library.collections[1]).map(\.key), ["1", "2"])
    }

    func testUpsertReplacesAndDropsTracksNoLongerHeld() {
        var library = WatchLibrary.empty
        library.upsert(album("a", ["1", "2"]), tracks: [track("1"), track("2")])
        library.upsert(album("b", ["3"]), tracks: [track("3")])
        library.upsert(album("a", ["2"]), tracks: [track("2")])

        XCTAssertEqual(library.collections.map(\.key), ["a", "b"])
        XCTAssertEqual(Set(library.tracks.keys), ["2", "3"])
    }

    func testWantedKeysFollowTheCollectionsAndListASharedSongOnce() {
        var library = WatchLibrary.empty
        library.upsert(album("a", ["1", "2"]), tracks: [track("1"), track("2")])
        library.upsert(album("b", ["3", "1"]), tracks: [track("3"), track("1")])

        XCTAssertEqual(library.wantedKeys, ["3", "1", "2"])
    }

    func testRemovingACollectionKeepsSongsAnotherOneHolds() {
        var library = WatchLibrary.empty
        library.upsert(album("a", ["1", "2"]), tracks: [track("1"), track("2")])
        library.upsert(album("b", ["2", "3"]), tracks: [track("2"), track("3")])
        library.removeCollection(key: "a")

        XCTAssertEqual(library.collections.map(\.key), ["b"])
        XCTAssertEqual(Set(library.tracks.keys), ["2", "3"])
    }

    func testSongsGatherInOneCollectionNewestFirst() {
        var library = WatchLibrary.empty
        library.addSongs([track("1")], at: Date(timeIntervalSince1970: 1))
        library.addSongs([track("2")], at: Date(timeIntervalSince1970: 2))
        library.addSongs([track("1")], at: Date(timeIntervalSince1970: 3))

        XCTAssertEqual(library.collections.count, 1)
        let songs = library.collection(key: WatchCollection.songsKey)
        XCTAssertEqual(songs?.kind, .songs)
        XCTAssertEqual(songs?.trackKeys, ["1", "2"])
        XCTAssertEqual(songs?.addedAt, Date(timeIntervalSince1970: 1))
    }

    func testRemovingTheLastSongRemovesTheSongsCollection() {
        var library = WatchLibrary.empty
        library.addSongs([track("1"), track("2")], at: .now)
        library.removeSong(key: "1")
        XCTAssertEqual(library.collection(key: WatchCollection.songsKey)?.trackKeys, ["2"])
        XCTAssertEqual(Set(library.tracks.keys), ["2"])

        library.removeSong(key: "2")
        XCTAssertNil(library.collection(key: WatchCollection.songsKey))
        XCTAssertTrue(library.tracks.isEmpty)
        XCTAssertTrue(library.isEmpty)
    }

    func testRevisionOnlyMovesForward() {
        var library = WatchLibrary.empty
        library.bumpRevision(now: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(library.revision, 1_000_000)
        // A clock that went back still moves the revision on.
        library.bumpRevision(now: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(library.revision, 1_000_001)
    }

    func testRoundTripsThroughJSON() throws {
        var library = WatchLibrary.empty
        library.upsert(album("a", ["1"]), tracks: [track("1")])
        library.addSongs([track("2")], at: Date(timeIntervalSince1970: 5))
        library.bumpRevision(now: Date(timeIntervalSince1970: 7))

        XCTAssertEqual(try WatchLibrary.decoded(from: library.encoded()), library)
    }

    func testTheSameSongSignedByEachDeviceIsTheSameDownload() {
        let origin = WatchTrackOrigin(source: .subsonic, contentID: "tr-1", sourceURL: URL(string: "https://s.example/rest/stream?id=tr-1&s=phone")!, audioCodec: "flac")
        let fromPhone = WatchTrack(key: "subsonic-tr-1", title: "S", artist: "A", streamURL: URL(string: "https://s.example/rest/stream?id=tr-1&format=mp3&s=phone")!, fileExtension: "mp3", origin: origin, quality: .high)
        let watchOrigin = WatchTrackOrigin(source: .subsonic, contentID: "tr-1", sourceURL: URL(string: "https://s.example/rest/stream?id=tr-1&s=watch")!, audioCodec: "flac")
        let fromWatch = WatchTrack(key: "subsonic-tr-1", title: "S", artist: "A", streamURL: URL(string: "https://s.example/rest/stream?id=tr-1&format=mp3&s=watch")!, fileExtension: "mp3", origin: watchOrigin, quality: .high)
        XCTAssertTrue(fromPhone.isSameDownload(as: fromWatch))

        let smaller = fromWatch.withStream(URL(string: "https://s.example/rest/stream?id=tr-1&format=mp3&maxBitRate=128")!, fileExtension: "mp3", quality: .small)
        XCTAssertFalse(fromPhone.isSameDownload(as: smaller))
        let original = fromWatch.withStream(origin.sourceURL, fileExtension: "flac", quality: .original)
        XCTAssertFalse(fromPhone.isSameDownload(as: original))

        // Songs from before origins were kept go by their URL.
        let legacy = WatchTrack(key: "1", title: "S", artist: "A", streamURL: URL(string: "https://s.example/1")!, fileExtension: "flac")
        XCTAssertTrue(legacy.isSameDownload(as: legacy))
        XCTAssertFalse(legacy.isSameDownload(as: legacy.withStream(URL(string: "https://s.example/2")!, fileExtension: "flac", quality: nil)))
    }
}
