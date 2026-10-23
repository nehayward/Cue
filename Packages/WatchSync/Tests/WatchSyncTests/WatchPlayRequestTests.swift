import XCTest
@testable import WatchSync

final class WatchPlayRequestTests: XCTestCase {
    private func songs(count: Int) -> [WatchPlayRequest.Song] {
        (0 ..< count).map { index in
            WatchPlayRequest.Song(
                source: .plex,
                id: "2b5d1c0f9a8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c%3A3%3A\(10_000 + index)",
                title: "A Fairly Long Song Title \(index)",
                artist: "Some Artist",
                album: "Some Album (Deluxe Edition)",
                artworkURL: URL(string: "https://192-168-1-20.0123456789abcdef.plex.direct:32400/photo/:/transcode?width=300&height=300&url=%2Flibrary%2Fmetadata%2F\(index)%2Fthumb&X-Plex-Token=abcdefghijklmnopqrst"),
                duration: 241,
                streamURL: URL(string: "https://192-168-1-20.0123456789abcdef.plex.direct:32400/library/parts/\(index)/1700000000/file.flac?X-Plex-Token=abcdefghijklmnopqrst")!,
                audioCodec: "flac"
            )
        }
    }

    func testARequestCrossesWhole() throws {
        let request = WatchPlayRequest(songs: songs(count: 12), startIndex: 4)
        let message = try WatchSyncMessage.playRequest(request)
        XCTAssertEqual(WatchSyncMessage.playRequest(in: message), request)
        XCTAssertEqual(request.startIndex, 4)
        // Not taken for any of the iPhone's other requests.
        XCTAssertNil(WatchSyncMessage.command(in: message))
        XCTAssertFalse(WatchSyncMessage.isNowPlayingRequest(message))
        XCTAssertNil(WatchSyncMessage.playRequest(in: WatchSyncMessage.nowPlayingRequest))
        XCTAssertNil(WatchSyncMessage.playRequest(in: [WatchSyncMessage.requestKey: "playSongs", WatchSyncMessage.playKey: Data([9, 9])]))
    }

    func testAStartPastTheEndStartsAtTheTop() {
        XCTAssertEqual(WatchPlayRequest(songs: songs(count: 3), startIndex: 7).startIndex, 0)
    }

    /// A long playlist goes from the song it starts at, so the message
    /// stays small.
    func testALongListGoesFromItsStart() {
        let all = songs(count: WatchPlayRequest.maximumSongs + 100)
        let request = WatchPlayRequest(songs: all, startIndex: 50)
        XCTAssertEqual(request.songs.count, WatchPlayRequest.maximumSongs)
        XCTAssertEqual(request.songs.first, all[50])
        XCTAssertEqual(request.startIndex, 0)
    }

    /// Messages are capped at about 64 KB. Linux has no LZFSE, so this runs
    /// on the plain size, which only has to stay under the cap packed.
    func testAFullRequestPacksSmall() throws {
        let message = try WatchSyncMessage.playRequest(WatchPlayRequest(songs: songs(count: WatchPlayRequest.maximumSongs)))
        #if canImport(Darwin)
        let packed = try XCTUnwrap(message[WatchSyncMessage.playKey] as? Data)
        XCTAssertLessThan(packed.count, 60_000)
        #endif
        XCTAssertEqual(WatchSyncMessage.playRequest(in: message)?.songs.count, WatchPlayRequest.maximumSongs)
    }

    /// The answer is what the iPhone plays then, with why not when the
    /// songs didn't start.
    func testAFailureCrossesInTheAnswer() throws {
        var answer = try WatchSyncMessage.nowPlayingMessage(nil)
        XCTAssertNil(WatchSyncMessage.playFailure(in: answer))
        answer.merge(WatchSyncMessage.playFailure("Open Cue on your iPhone.")) { _, new in new }
        XCTAssertEqual(WatchSyncMessage.playFailure(in: answer), "Open Cue on your iPhone.")
        XCTAssertTrue(WatchSyncMessage.carriesNowPlaying(answer))
    }
}
