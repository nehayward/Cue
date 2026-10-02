import XCTest
@testable import WatchSync

final class WatchWidgetStateTests: XCTestCase {
    func testItComesBackAsSaved() throws {
        let suite = "WatchWidgetStateTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(WatchWidgetState.load(from: defaults), .empty)
        let state = WatchWidgetState(songsOnWatch: 124, songsToDownload: 12, bytesUsed: 987_654_321, nowPlayingTitle: "Song", nowPlayingArtist: "Artist", isPlaying: true)
        state.save(to: defaults)
        XCTAssertEqual(WatchWidgetState.load(from: defaults), state)
    }
}
