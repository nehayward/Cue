import XCTest
@testable import SonosKit

/// `Room.playbackPosition` only moves when something writes it, and with the
/// app off screen almost nothing does. These pin the two rules that keep it
/// honest anyway: it changes with the track, and it catches up on return.
final class RoomPlaybackPositionTests: XCTestCase {

    private func makeRoom() -> Room {
        Room(id: "RINCON_TEST", ip: "192.168.0.2", name: "Kitchen")
    }

    // MARK: - Track change

    /// The Lock Screen bug: the title moved on but the scrubber carried on from
    /// the previous song, because nothing wrote the new song's position.
    func testNewTrackBringsItsOwnPosition() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "Harder to Breathe", duration: 173_000, playbackPosition: 0)
        room.playbackPosition = 170_000

        room.track = Track(trackID: "b", name: "This Love", duration: 206_000, playbackPosition: 400)

        XCTAssertEqual(room.playbackPosition, 400)
    }

    /// Duration and artist reconcile in place a pulse late; that's the same
    /// song and must not touch the position.
    func testEditingTheSameTrackKeepsThePosition() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", playbackPosition: 0)
        room.playbackPosition = 90_000

        room.track.duration = 206_000
        room.track.artist = "Maroon 5"

        XCTAssertEqual(room.playbackPosition, 90_000)
    }

    // MARK: - Estimate

    func testEstimateRunsOnFromTheLastReport() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true
        room.playbackPosition = 30_000

        let estimate = room.estimatedPlaybackPosition(at: room.playbackPositionStampedAt.addingTimeInterval(60))

        XCTAssertEqual(estimate, 90_000, accuracy: 1)
        XCTAssertEqual(room.playbackPosition, 30_000, "estimating doesn't write the model")
    }

    func testEstimateStopsAtTheEndOfTheTrack() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true
        room.playbackPosition = 200_000

        let estimate = room.estimatedPlaybackPosition(at: room.playbackPositionStampedAt.addingTimeInterval(600))

        XCTAssertEqual(estimate, 206_000)
    }

    func testEstimateHoldsStillWhilePaused() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.playbackPosition = 30_000

        let estimate = room.estimatedPlaybackPosition(at: room.playbackPositionStampedAt.addingTimeInterval(60))

        XCTAssertEqual(estimate, 30_000)
    }

    /// Resuming restarts the clock: a song paused for ten minutes and resumed
    /// a moment ago is a moment in, not ten minutes in.
    func testTimeSpentPausedDoesNotCount() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.playbackPosition = 30_000
        room.isPlaying = true
        let resumedAt = room.playbackPositionStampedAt

        XCTAssertEqual(room.estimatedPlaybackPosition(at: resumedAt.addingTimeInterval(5)), 35_000, accuracy: 1)
    }

    /// Pausing keeps what the bar was showing instead of snapping back to the
    /// last report.
    func testPausingKeepsTheRunningPosition() throws {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true
        room.playbackPosition = 30_000
        Thread.sleep(forTimeInterval: 0.3)

        room.isPlaying = false

        XCTAssertGreaterThanOrEqual(room.playbackPosition, 30_300)
        // Generous: only here to show it didn't run on without bound.
        XCTAssertLessThan(room.playbackPosition, 35_000)
    }

    // MARK: - Reports

    /// A poll reads the position a round trip before it lands. Taking it would
    /// pull the bar back by that much every time.
    func testALaggingReportIsIgnoredWhilePlaying() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true
        room.playbackPosition = 30_000

        room.updatePlaybackPosition(29_700)

        XCTAssertEqual(room.playbackPosition, 30_000)
    }

    func testAJumpIsTaken() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true
        room.playbackPosition = 30_000

        room.updatePlaybackPosition(150_000)

        XCTAssertEqual(room.playbackPosition, 150_000)
    }

    func testReportsAreTakenAsIsWhilePaused() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.playbackPosition = 30_000

        room.updatePlaybackPosition(30_400)

        XCTAssertEqual(room.playbackPosition, 30_400)
    }

    // MARK: - Seeking

    /// The seek goes out in whole seconds, so the bar goes to the second the
    /// speaker will actually land on, not where the finger stopped.
    func testSeekLandsOnTheWholeSecondSent() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true

        room.beginSeek(to: 65_800)

        XCTAssertEqual(room.playbackPosition, 65_000)
        XCTAssertEqual(room.seekTarget, 65_000)
    }

    /// The speaker buffers before playing again; the bar waits with it.
    func testTheBarHoldsUntilTheSeekIsConfirmed() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true
        room.beginSeek(to: 65_000)

        let estimate = room.estimatedPlaybackPosition(at: .now.addingTimeInterval(1))

        XCTAssertEqual(estimate, 65_000)
    }

    /// A poll that was in flight when the seek went out reports the old spot.
    func testAReportFromBeforeTheSeekIsIgnored() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true
        room.playbackPosition = 20_000
        room.beginSeek(to: 150_000)

        room.updatePlaybackPosition(20_600)

        XCTAssertEqual(room.playbackPosition, 150_000)
        XCTAssertNotNil(room.seekTarget)
    }

    /// The speaker reports the target itself the whole time it buffers, and
    /// polls repeat it. That isn't playback resuming.
    func testReportingTheTargetItselfKeepsHolding() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true
        room.beginSeek(to: 96_000)

        room.updatePlaybackPosition(96_000)

        XCTAssertEqual(room.seekTarget, 96_000)
        XCTAssertEqual(room.estimatedPlaybackPosition(at: .now.addingTimeInterval(1.5)), 96_000)
    }

    /// The trace behind this: BUFFERING at the target confirmed the seek after
    /// 45 ms, the bar ran for the ~1.5 s the speaker buffered, and the next
    /// poll pulled it back.
    func testBufferingPastTheTargetKeepsHolding() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true
        room.beginSeek(to: 96_000)
        room.isTransitioning = true

        room.updatePlaybackPosition(96_200)

        XCTAssertEqual(room.seekTarget, 96_000)
    }

    func testMovingPastTheTargetWhilePlayingConfirmsTheSeek() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true
        room.beginSeek(to: 96_000)

        room.updatePlaybackPosition(96_155)

        XCTAssertNil(room.seekTarget)
        XCTAssertEqual(room.playbackPosition, 96_155)
        XCTAssertEqual(room.estimatedPlaybackPosition(at: room.playbackPositionStampedAt.addingTimeInterval(2)), 98_155, accuracy: 1,
                       "runs again from the confirmation")
    }

    // MARK: - Transitioning

    func testTheClockHoldsWhileTransitioning() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true
        room.playbackPosition = 30_000
        room.isTransitioning = true

        XCTAssertEqual(room.estimatedPlaybackPosition(at: .now.addingTimeInterval(2)), room.playbackPosition, accuracy: 1)
    }

    func testTheClockRestartsWhenTransitioningEnds() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true
        room.isTransitioning = true
        room.playbackPosition = 30_000

        room.isTransitioning = false
        let resumedAt = room.playbackPositionStampedAt

        XCTAssertEqual(room.estimatedPlaybackPosition(at: resumedAt.addingTimeInterval(1)), 31_000, accuracy: 1)
    }

    /// Paused rooms were rewritten with the same number on every poll.
    func testAnUnchangedReportWhilePausedIsNotWritten() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.playbackPosition = 155_000
        let stamped = room.playbackPositionStampedAt

        room.updatePlaybackPosition(155_000)

        XCTAssertEqual(room.playbackPositionStampedAt, stamped)
    }

    /// If no report ever comes, the bar runs rather than sit there.
    func testAnUnconfirmedSeekRunsAfterTheTimeout() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true
        room.beginSeek(to: 150_000)

        let later = room.playbackPositionStampedAt.addingTimeInterval(Room.seekTimeout + 1)

        XCTAssertEqual(room.estimatedPlaybackPosition(at: later), 150_000 + (Room.seekTimeout + 1) * 1000, accuracy: 1)
    }

    func testAnExpiredSeekStopsFilteringReports() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true
        let seekAt = Date.now.addingTimeInterval(-(Room.seekTimeout + 1))
        room.beginSeek(to: 150_000, at: seekAt)

        room.updatePlaybackPosition(20_000)

        XCTAssertEqual(room.playbackPosition, 20_000)
    }

    func testANewTrackEndsTheSeek() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true
        room.beginSeek(to: 150_000)

        room.track = Track(trackID: "b", name: "She Will Be Loved", duration: 257_000, playbackPosition: 300)

        XCTAssertNil(room.seekTarget)
        XCTAssertEqual(room.playbackPosition, 300)
    }

    // MARK: - Skipping

    /// The old song keeps being reported for a moment after the command; it
    /// mustn't pull the bar back to where that song was.
    func testASkipIgnoresTheOutgoingSong() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true
        room.playbackPosition = 120_000

        room.beginSkip()
        room.updatePlaybackPosition(121_000)

        XCTAssertEqual(room.playbackPosition, 0)
    }

    func testTheNextSongEndsTheSkip() {
        let room = makeRoom()
        room.track = Track(trackID: "a", name: "This Love", duration: 206_000)
        room.isPlaying = true
        room.playbackPosition = 120_000
        room.beginSkip()

        room.track = Track(trackID: "b", name: "Shiver", duration: 180_000, playbackPosition: 250)

        XCTAssertNil(room.seekTarget)
        XCTAssertEqual(room.playbackPosition, 250)
    }
}
