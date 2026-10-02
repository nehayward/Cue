import XCTest
@testable import SonosKit

/// Pins the arithmetic behind instant skipping. The failure this replaced was
/// mashing next: every press became its own command, the speaker worked
/// through them one stream-open at a time, and the song kept changing for
/// seconds after the last press.
final class TrackSkipPlanTests: XCTestCase {

    private let midSong: TimeInterval = 90_000  // ms
    private let songStart: TimeInterval = 0

    // MARK: - Queue mode

    func testPressesWhileAJumpIsInFlightCostOneMoreJump() {
        var plan = TrackSkipPlan(mode: .queue(wrapsAround: false), startPosition: 5)

        plan.press(.next, playbackPosition: midSong, queueTotal: 20)
        XCTAssertEqual(plan.nextCommand, .jump(to: 6))
        plan.didSend(.jump(to: 6))

        // Four more presses land while that jump was on its way.
        for _ in 0..<4 { plan.press(.next, playbackPosition: songStart, queueTotal: 20) }

        XCTAssertEqual(plan.nextCommand, .jump(to: 10), "one jump to where the presses add up to, not four skips")
        plan.didSend(.jump(to: 10))
        XCTAssertNil(plan.nextCommand)
        XCTAssertEqual(plan.commandsSent, 2)
    }

    func testPressesThatCancelOutSendNothing() {
        var plan = TrackSkipPlan(mode: .queue(wrapsAround: false), startPosition: 5)
        plan.press(.next, playbackPosition: songStart, queueTotal: 20)
        plan.press(.previous, playbackPosition: songStart, queueTotal: 20)

        XCTAssertEqual(plan.target, 5)
        XCTAssertNil(plan.nextCommand)
    }

    func testNextStopsAtTheEndOfAQueueThatDoesNotRepeat() {
        var plan = TrackSkipPlan(mode: .queue(wrapsAround: false), startPosition: 20)
        XCTAssertFalse(plan.press(.next, playbackPosition: songStart, queueTotal: 20))
        XCTAssertNil(plan.nextCommand)
    }

    func testRepeatAllWrapsBothWays() {
        var forward = TrackSkipPlan(mode: .queue(wrapsAround: true), startPosition: 20)
        forward.press(.next, playbackPosition: songStart, queueTotal: 20)
        XCTAssertEqual(forward.nextCommand, .jump(to: 1))

        var backward = TrackSkipPlan(mode: .queue(wrapsAround: true), startPosition: 1)
        backward.press(.previous, playbackPosition: songStart, queueTotal: 20)
        XCTAssertEqual(backward.nextCommand, .jump(to: 20))
    }

    /// The length isn't known until the first preview fetch lands. Clamping to
    /// a guess would stop short; the speaker refuses a jump that's really past
    /// the end, and the sender treats that as the end of the run.
    func testUnknownQueueLengthDoesNotClampForward() {
        var plan = TrackSkipPlan(mode: .queue(wrapsAround: false), startPosition: 5)
        plan.press(.next, playbackPosition: songStart, queueTotal: 0)
        XCTAssertEqual(plan.nextCommand, .jump(to: 6))
    }

    func testPreviousOnTheFirstSongRestartsIt() {
        var plan = TrackSkipPlan(mode: .queue(wrapsAround: false), startPosition: 1)
        XCTAssertTrue(plan.press(.previous, playbackPosition: songStart, queueTotal: 20))
        XCTAssertEqual(plan.nextCommand, .restart)
    }

    // MARK: - Previous

    func testPreviousPastThreeSecondsRestartsAndThenGoesBack() {
        var plan = TrackSkipPlan(mode: .queue(wrapsAround: false), startPosition: 5)

        plan.press(.previous, playbackPosition: midSong, queueTotal: 20)
        XCTAssertEqual(plan.target, 5)
        XCTAssertEqual(plan.nextCommand, .restart)

        // The first press zeroed the player, so the second goes back a song —
        // and the jump makes the queued restart redundant.
        plan.press(.previous, playbackPosition: songStart, queueTotal: 20)
        XCTAssertEqual(plan.nextCommand, .jump(to: 4))
        plan.didSend(.jump(to: 4))
        XCTAssertNil(plan.nextCommand)
    }

    func testPreviousWithinThreeSecondsGoesBack() {
        var plan = TrackSkipPlan(mode: .queue(wrapsAround: false), startPosition: 5)
        plan.press(.previous, playbackPosition: 2_000, queueTotal: 20)
        XCTAssertEqual(plan.nextCommand, .jump(to: 4))
    }

    // MARK: - Relative mode

    func testRelativeSkipsGoOutOneAtATimeInOrder() {
        var plan = TrackSkipPlan(mode: .relative, startPosition: 1)
        plan.press(.previous, playbackPosition: midSong, queueTotal: 0)
        plan.press(.next, playbackPosition: songStart, queueTotal: 0)
        plan.press(.next, playbackPosition: songStart, queueTotal: 0)

        XCTAssertEqual(plan.nextCommand, .restart, "the restart came first")
        plan.didSend(.restart)
        XCTAssertEqual(plan.nextCommand, .step(forward: true))
        plan.didSend(.step(forward: true))
        XCTAssertEqual(plan.nextCommand, .step(forward: true))
        plan.didSend(.step(forward: true))
        XCTAssertNil(plan.nextCommand)
        XCTAssertEqual(plan.netSteps, 2)
    }

    // MARK: - Confirmation

    func testQueueModeConfirmsOnTheTargetPositionOnly() {
        var plan = TrackSkipPlan(mode: .queue(wrapsAround: false), startPosition: 5)
        plan.press(.next, playbackPosition: songStart, queueTotal: 20)
        plan.press(.next, playbackPosition: songStart, queueTotal: 20)
        plan.didSend(.jump(to: 7))

        XCTAssertFalse(plan.isConfirmed(position: 6, isStartTrack: false), "an intermediate song isn't arrival")
        XCTAssertTrue(plan.isConfirmed(position: 7, isStartTrack: false))
    }

    func testRelativeModeConfirmsOnceTheSpeakerHasLeftTheStartingSong() {
        var plan = TrackSkipPlan(mode: .relative, startPosition: 1)
        plan.press(.next, playbackPosition: songStart, queueTotal: 0)
        plan.didSend(.step(forward: true))

        XCTAssertFalse(plan.isConfirmed(position: 1, isStartTrack: true))
        XCTAssertTrue(plan.isConfirmed(position: 1, isStartTrack: false))
    }

    func testRelativeRestartConfirmsOnTheSameSong() {
        var plan = TrackSkipPlan(mode: .relative, startPosition: 1)
        plan.press(.previous, playbackPosition: midSong, queueTotal: 0)
        plan.didSend(.restart)

        XCTAssertTrue(plan.isConfirmed(position: 1, isStartTrack: true))
    }
}
