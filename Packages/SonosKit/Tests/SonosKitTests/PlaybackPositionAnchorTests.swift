import XCTest
@testable import SonosKit

/// The two failures these pin were both visible on the Lock Screen: the scrubber
/// appearing to stop, and pausing snapping it back to the start of the track.
/// Both came from treating `Room.playbackPosition` as if it advanced on its own.
/// It doesn't — it only moves when a socket event or the SOAP poll writes it,
/// and the poll is cancelled while backgrounded.
final class PlaybackPositionAnchorTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let trackDuration: TimeInterval = 200_000  // ms

    // MARK: - First resolve

    func testFirstResolveTakesTheSpeakersPosition() {
        var anchor = PlaybackPositionAnchor()
        let result = anchor.resolve(modelElapsed: 20_000, duration: trackDuration, now: start)
        XCTAssertEqual(result.elapsed, 20_000)
    }

    // MARK: - Frozen model

    /// The regression behind "playback stops after a track change": backgrounded,
    /// the model freezes at the last reported position while the system's
    /// interpolation correctly moves on. Re-anchoring to the frozen value drags
    /// the scrubber backwards, which reads as playback having stopped.
    func testFrozenModelDoesNotDragThePositionBackwards() {
        var anchor = PlaybackPositionAnchor()
        _ = anchor.resolve(modelElapsed: 20_000, duration: trackDuration, now: start)
        anchor.commit(elapsed: 20_000, isPlaying: true, at: start)

        // 60s later the speaker has reported nothing new.
        let later = start.addingTimeInterval(60)
        let result = anchor.resolve(modelElapsed: 20_000, duration: trackDuration, now: later)

        XCTAssertEqual(result.elapsed, 80_000, accuracy: 1,
                       "should carry the interpolation forward, not re-state the frozen 20s")
        XCTAssertFalse(result.drifted, "an unmoved model is not drift — it's just stale")
    }

    /// The regression behind "pausing clears the progress". A pause changes the
    /// snapshot, so it always publishes; publishing the stale model position sent
    /// the scrubber back to wherever the last `playbackStatus` landed.
    func testPausingKeepsThePositionTheUserCanSee() {
        var anchor = PlaybackPositionAnchor()
        _ = anchor.resolve(modelElapsed: 5_000, duration: trackDuration, now: start)
        anchor.commit(elapsed: 5_000, isPlaying: true, at: start)

        // Two minutes of playback later, the user pauses. The model still holds
        // the 5s reading from the last event.
        let pausedAt = start.addingTimeInterval(120)
        let result = anchor.resolve(modelElapsed: 5_000, duration: trackDuration, now: pausedAt)

        XCTAssertEqual(result.elapsed, 125_000, accuracy: 1)
    }

    // MARK: - Real movement

    func testASeekReAnchorsAndReportsDrift() {
        var anchor = PlaybackPositionAnchor()
        _ = anchor.resolve(modelElapsed: 20_000, duration: trackDuration, now: start)
        anchor.commit(elapsed: 20_000, isPlaying: true, at: start)

        // The user scrubs to 150s; the speaker reports it.
        let seekedAt = start.addingTimeInterval(10)
        let result = anchor.resolve(modelElapsed: 150_000, duration: trackDuration, now: seekedAt)

        XCTAssertEqual(result.elapsed, 150_000)
        XCTAssertTrue(result.drifted, "a seek is worth a republish on its own")
    }

    /// A poll result a second or so off what the system is already showing isn't
    /// worth correcting — republishing that would only risk visible jitter.
    func testSmallDisagreementIsNotDrift() {
        var anchor = PlaybackPositionAnchor()
        _ = anchor.resolve(modelElapsed: 20_000, duration: trackDuration, now: start)
        anchor.commit(elapsed: 20_000, isPlaying: true, at: start)

        let later = start.addingTimeInterval(10)
        // System shows ~30s; the speaker says 30.5s.
        let result = anchor.resolve(modelElapsed: 30_500, duration: trackDuration, now: later)

        XCTAssertFalse(result.drifted)
        XCTAssertEqual(result.elapsed, 30_500, "still publishes the fresh number when it does publish")
    }

    // MARK: - Paused anchors don't interpolate

    func testInterpolationStopsWhilePaused() {
        var anchor = PlaybackPositionAnchor()
        _ = anchor.resolve(modelElapsed: 40_000, duration: trackDuration, now: start)
        anchor.commit(elapsed: 40_000, isPlaying: false, at: start)

        let later = start.addingTimeInterval(300)
        let result = anchor.resolve(modelElapsed: 40_000, duration: trackDuration, now: later)

        XCTAssertEqual(result.elapsed, 40_000, "a paused card must not creep forward")
    }

    // MARK: - Clamping

    func testInterpolationIsClampedToTheTrackLength() {
        var anchor = PlaybackPositionAnchor()
        _ = anchor.resolve(modelElapsed: 190_000, duration: trackDuration, now: start)
        anchor.commit(elapsed: 190_000, isPlaying: true, at: start)

        // The track ended and nothing reported it — interpolation would run past
        // the end.
        let later = start.addingTimeInterval(60)
        let result = anchor.resolve(modelElapsed: 190_000, duration: trackDuration, now: later)

        XCTAssertEqual(result.elapsed, trackDuration)
    }

    /// Radio and line-in report no duration, so there's nothing to clamp to —
    /// but it still must not go negative.
    func testLiveStreamIsNotClampedButStaysNonNegative() {
        var anchor = PlaybackPositionAnchor()
        _ = anchor.resolve(modelElapsed: 0, duration: 0, now: start)
        anchor.commit(elapsed: 0, isPlaying: true, at: start)

        let later = start.addingTimeInterval(3_600)
        let result = anchor.resolve(modelElapsed: 0, duration: 0, now: later)

        XCTAssertEqual(result.elapsed, 3_600_000, accuracy: 1)
    }

    // MARK: - Reset

    /// The song-change failure. Skipping writes `playbackPosition = 0`
    /// optimistically, and the incoming track reports ~0 too — so "the model
    /// didn't move" is read as "keep counting" and a song that just started
    /// shows several seconds in. The service resets the anchor on a track
    /// change; this pins what that reset has to achieve.
    func testUnchangedPositionAcrossATrackChangeDoesNotKeepCounting() {
        var anchor = PlaybackPositionAnchor()
        _ = anchor.resolve(modelElapsed: 0, duration: trackDuration, now: start)
        anchor.commit(elapsed: 0, isPlaying: true, at: start)

        // Ten seconds later the next track begins, also reporting 0.
        let nextTrack = start.addingTimeInterval(10)
        let withoutReset = anchor.resolve(modelElapsed: 0, duration: trackDuration, now: nextTrack)
        XCTAssertEqual(withoutReset.elapsed, 10_000, accuracy: 1,
                       "without a reset the anchor carries the old timeline across the boundary")

        anchor.reset()
        let afterReset = anchor.resolve(modelElapsed: 0, duration: trackDuration, now: nextTrack)
        XCTAssertEqual(afterReset.elapsed, 0, "a new song starts at the position the speaker reports")
    }

    func testResetTakesTheSpeakersPositionAgain() {
        var anchor = PlaybackPositionAnchor()
        _ = anchor.resolve(modelElapsed: 20_000, duration: trackDuration, now: start)
        anchor.commit(elapsed: 20_000, isPlaying: true, at: start)

        anchor.reset()

        // New track: same reported position as before, but nothing carried over.
        let later = start.addingTimeInterval(60)
        let result = anchor.resolve(modelElapsed: 20_000, duration: trackDuration, now: later)

        XCTAssertEqual(result.elapsed, 20_000)
    }
}
