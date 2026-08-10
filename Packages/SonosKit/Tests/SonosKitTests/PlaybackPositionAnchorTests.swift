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

    // MARK: - The scrubber's clock

    /// `position` is pure, and this is why that matters as much as the number it
    /// returns: reading the clock is not a state change, so a view can do it on
    /// a `TimelineView` schedule without writing anything or invalidating
    /// anything. A version that re-committed on every read cost real CPU in the
    /// background, where the app stays alive holding the Now Playing session.
    func testPositionMovesWithoutBeingSeated() {
        var anchor = PlaybackPositionAnchor()
        anchor.seat(modelElapsed: 20_000, duration: trackDuration, isPlaying: true, now: start)

        // A quarter second on the speaker still reads 20s — it will until the
        // truncated value rolls over — and nothing has re-seated the anchor.
        let quarter = start.addingTimeInterval(0.25)

        XCTAssertEqual(anchor.position(at: quarter, duration: trackDuration), 20_250, accuracy: 1)
    }

    /// Nil rather than zero, so the caller can fall back to the speaker's own
    /// reading. Returning the empty anchor's zero flashed the bar to the start
    /// of the track on the first render.
    func testPositionIsNilUntilSeated() {
        let anchor = PlaybackPositionAnchor()
        XCTAssertNil(anchor.position(at: start, duration: trackDuration))
    }

    /// The reason the scrubber's bias is the opposite of the card's.
    /// `Room.playbackPosition` is parsed from `RelTime` (`h:mm:ss`), so every
    /// reading is truncated to a whole second — a *correct* interpolation
    /// legitimately sits above it, and must not be dragged back down.
    func testSeatIgnoresATruncatedReadingBelowTheInterpolation() {
        var anchor = PlaybackPositionAnchor()
        anchor.seat(modelElapsed: 20_000, duration: trackDuration, isPlaying: true, now: start)

        // 1.5s on: the clock says 21.5s, the speaker's truncated reading says 21s.
        let later = start.addingTimeInterval(1.5)
        anchor.seat(modelElapsed: 21_000, duration: trackDuration, isPlaying: true, now: later)

        XCTAssertEqual(anchor.position(at: later, duration: trackDuration), 21_500, accuracy: 1,
                       "truncation is not drift — it must not snap backwards")
    }

    /// Real movement still wins. This is what the tolerance is there to let
    /// through: someone scrubbed, skipped, or moved the track elsewhere.
    func testSeatFollowsARealSeek() {
        var anchor = PlaybackPositionAnchor()
        anchor.seat(modelElapsed: 20_000, duration: trackDuration, isPlaying: true, now: start)

        let seekedAt = start.addingTimeInterval(1)
        anchor.seat(modelElapsed: 150_000, duration: trackDuration, isPlaying: true, now: seekedAt)

        XCTAssertEqual(anchor.position(at: seekedAt, duration: trackDuration), 150_000)
    }

    /// The first seat after a reset has no timeline to interpolate along.
    /// Falling through to the interpolation there anchors at zero, which leaves
    /// the rest of the track running a second short.
    func testFirstSeatTakesTheSpeakersPosition() {
        var anchor = PlaybackPositionAnchor()

        // Under the drift tolerance, so an implementation that preferred its own
        // (empty) interpolation would start the song at 0.
        anchor.seat(modelElapsed: 1_000, duration: trackDuration, isPlaying: true, now: start)

        XCTAssertEqual(anchor.position(at: start, duration: trackDuration), 1_000)
    }

    /// A pause is a rate change, and the view re-seats on it. The freeze has to
    /// happen at the interpolated position, not at the stale reading.
    func testPausingFreezesWhereTheClockHadCountedTo() {
        var anchor = PlaybackPositionAnchor()
        anchor.seat(modelElapsed: 40_000, duration: trackDuration, isPlaying: true, now: start)

        // 10s later the user pauses; the speaker's last reading is still 40s.
        let pausedAt = start.addingTimeInterval(10)
        anchor.seat(modelElapsed: 40_000, duration: trackDuration, isPlaying: false, now: pausedAt)

        let muchLater = pausedAt.addingTimeInterval(300)
        XCTAssertEqual(anchor.position(at: muchLater, duration: trackDuration), 50_000, accuracy: 1)
    }

    func testPositionIsClampedToTheTrackLength() {
        var anchor = PlaybackPositionAnchor()
        anchor.seat(modelElapsed: 190_000, duration: trackDuration, isPlaying: true, now: start)

        let later = start.addingTimeInterval(60)
        XCTAssertEqual(anchor.position(at: later, duration: trackDuration), trackDuration)
    }

    /// The two surfaces the change exists to reconcile: the card publishes an
    /// anchor and lets the system interpolate, the player screen interpolates
    /// locally. Given the same readings they have to end up at the same number.
    func testTheScrubberAndTheCardAgreeOnTheSameReadings() {
        var card = PlaybackPositionAnchor()
        var screen = PlaybackPositionAnchor()

        let published = card.resolve(modelElapsed: 20_000, duration: trackDuration, now: start)
        card.commit(elapsed: published.elapsed, isPlaying: true, at: start)
        screen.seat(modelElapsed: 20_000, duration: trackDuration, isPlaying: true, now: start)

        // 30s of playback. The card is never republished — nothing changed — so
        // its number is the system's interpolation from the anchor.
        let later = start.addingTimeInterval(30)
        let cardPosition = published.elapsed + 30_000
        // The speaker has meanwhile reported a truncated 49s (it is at 50s).
        screen.seat(modelElapsed: 49_000, duration: trackDuration, isPlaying: true, now: later)

        XCTAssertEqual(screen.position(at: later, duration: trackDuration), cardPosition, accuracy: 1)
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
