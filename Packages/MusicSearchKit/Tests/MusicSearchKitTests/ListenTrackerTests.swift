@testable import MusicSearchKit
import XCTest

final class ListenTrackerTests: XCTestCase {

    /// Plays from `start` to `end` in half-second polls, returning how many
    /// readings said the play counted.
    private func play(_ tracker: inout ListenTracker, from start: TimeInterval, to end: TimeInterval) -> Int {
        var counted = 0
        var position = start
        while position <= end {
            if tracker.advance(to: position) { counted += 1 }
            position += 0.5
        }
        return counted
    }

    func testCountsAtHalfwayForAShortSong() {
        var tracker = ListenTracker(duration: 180)
        XCTAssertEqual(tracker.threshold, 90)
        XCTAssertEqual(play(&tracker, from: 0, to: 89.5), 0)
        XCTAssertFalse(tracker.hasCounted)
        XCTAssertEqual(play(&tracker, from: 90, to: 91), 1)
        XCTAssertTrue(tracker.hasCounted)
    }

    func testCountsAtFourMinutesForALongSong() {
        var tracker = ListenTracker(duration: 20 * 60)
        XCTAssertEqual(tracker.threshold, 240)
        XCTAssertEqual(play(&tracker, from: 0, to: 300), 1)
    }

    func testCountsOnlyOnce() {
        var tracker = ListenTracker(duration: 60)
        XCTAssertEqual(play(&tracker, from: 0, to: 60), 1)
        tracker.pause()
        XCTAssertEqual(play(&tracker, from: 0, to: 60), 0)
    }

    func testSongsUnderThirtySecondsNeverCount() {
        var tracker = ListenTracker(duration: 29)
        XCTAssertNil(tracker.threshold)
        XCTAssertEqual(play(&tracker, from: 0, to: 29), 0)
    }

    func testUnknownDurationWaitsUntilKnown() {
        var tracker = ListenTracker(duration: 0)
        XCTAssertEqual(play(&tracker, from: 0, to: 100), 0)
        // The length arrives once the player has read it; what was heard
        // meanwhile still counts toward the threshold.
        tracker.duration = 180
        XCTAssertTrue(tracker.advance(to: 100.5))
    }

    func testSeekingForwardIsNotListening() {
        var tracker = ListenTracker(duration: 200)
        XCTAssertEqual(play(&tracker, from: 0, to: 10), 0)
        // Jump to near the end: the jump itself adds nothing.
        XCTAssertFalse(tracker.advance(to: 190))
        XCTAssertEqual(tracker.listened, 10, accuracy: 0.001)
    }

    func testSeekingBackKeepsWhatWasHeard() {
        var tracker = ListenTracker(duration: 100)
        XCTAssertEqual(play(&tracker, from: 0, to: 40), 0)
        XCTAssertFalse(tracker.advance(to: 0))
        XCTAssertEqual(tracker.listened, 40, accuracy: 0.001)
        XCTAssertEqual(play(&tracker, from: 0.5, to: 10), 1)
    }

    func testPauseDropsTheStepAcrossIt() {
        var tracker = ListenTracker(duration: 100)
        XCTAssertEqual(play(&tracker, from: 0, to: 10), 0)
        tracker.pause()
        // Scrubbed a few seconds on while paused, then resumed.
        XCTAssertFalse(tracker.advance(to: 14))
        XCTAssertEqual(tracker.listened, 10, accuracy: 0.001)
    }

    func testALatePollStillCounts() {
        var tracker = ListenTracker(duration: 100)
        XCTAssertFalse(tracker.advance(to: 0))
        XCTAssertFalse(tracker.advance(to: 4))
        XCTAssertEqual(tracker.listened, 4, accuracy: 0.001)
    }
}
