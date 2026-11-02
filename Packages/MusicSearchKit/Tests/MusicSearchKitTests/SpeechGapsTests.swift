import XCTest
@testable import MusicSearchKit

final class SpeechGapsTests: XCTestCase {
    /// A trace of 10 ms windows from `start`, each stretch at its level.
    private func trace(from start: TimeInterval = 0, _ stretches: [(seconds: TimeInterval, level: Float)]) -> LoudnessTrace {
        var times: [TimeInterval] = []
        var levels: [Float] = []
        var time = start
        for stretch in stretches {
            for _ in 0 ..< Int((stretch.seconds / 0.01).rounded()) {
                times.append(time)
                levels.append(stretch.level)
                time += 0.01
            }
        }
        return LoudnessTrace(times: times, levels: levels, windowLength: 0.01)
    }

    private let voice: Float = -20
    private let room: Float = -65

    /// Speech to 8 s: gaps between words at 1, 2, 5, 6.2 and 7 s, and the
    /// end of a sentence from 3 to 3.5 s.
    private var narration: LoudnessTrace {
        trace([
            (1, voice), (0.12, room), (0.88, voice), (0.12, room), (0.88, voice),
            (0.5, room),
            (1.5, voice), (0.12, room), (1.08, voice), (0.12, room), (0.68, voice), (0.12, room), (0.88, voice),
        ])
    }

    func testShortPauseLandsInTheNearestGapBetweenWords() throws {
        let landing = try XCTUnwrap(SpeechGaps.landing(near: 6, before: 8, prefersSentences: false, in: narration))
        XCTAssertEqual(landing, 6.26, accuracy: 0.011)
    }

    func testLongPauseGoesBackToTheEndOfASentence() throws {
        let landing = try XCTUnwrap(SpeechGaps.landing(near: 5, before: 8, prefersSentences: true, in: narration))
        // Just before the voice comes back.
        XCTAssertEqual(landing, 3.38, accuracy: 0.011)
    }

    func testNeverBeforeTheFloor() {
        XCTAssertNil(SpeechGaps.landing(near: 4, before: 8, notBefore: 3.6, prefersSentences: true, in: narration))
    }

    func testNeverRightAtThePause() throws {
        // The gap at 7 s is past the latest it may land, 7.7 s.
        let landing = try XCTUnwrap(SpeechGaps.landing(near: 7.5, before: 8, prefersSentences: false, in: narration))
        XCTAssertEqual(landing, 7.06, accuracy: 0.011)
        XCTAssertNil(SpeechGaps.landing(near: 7.5, before: 7.3, prefersSentences: false, in: narration))
    }

    func testNothingClearIsLeftAlone() {
        // Music: loud all through, a little up and down.
        let music = trace((0 ..< 80).map { (0.1, $0.isMultiple(of: 2) ? Float(-18) : Float(-24)) })
        XCTAssertNil(SpeechGaps.landing(near: 6, before: 8, prefersSentences: false, in: music))
        // The target before the trace starts.
        XCTAssertNil(SpeechGaps.landing(near: 6, before: 8, prefersSentences: false, in: trace(from: 6, [(2, voice)])))
    }

    func testDigitalSilenceDoesNotHideRoomTone() throws {
        // Sentences end in digital silence; the gaps between words are room tone.
        let edited = trace([(2, -100), (1, voice), (0.12, -62), (1, voice), (0.5, -100), (2, voice)])
        let landing = try XCTUnwrap(SpeechGaps.landing(near: 3.2, before: 6.6, prefersSentences: false, in: edited))
        XCTAssertEqual(landing, 3.06, accuracy: 0.011)
    }

    func testSmartResumeLandsInAPauseOnTheBooksClock() {
        // File 2 starts at 100 s in the book; its audio was heard to 108 s.
        let heard = narration.shifted(by: 100)
        let chapters = [AudiobookChapter(id: 0, title: "One", start: 0, end: 100), AudiobookChapter(id: 1, title: "Two", start: 100, end: 500)]
        // 3 min paused: back 3 s, to 105 s, then the end of the sentence.
        XCTAssertEqual(SmartResume.resumeTime(from: 108, afterPausing: 3 * 60, chapters: chapters, heard: heard), 103.38, accuracy: 0.011)
        // 20 s paused: back 2 s, to 106 s, then the gap between words.
        XCTAssertEqual(SmartResume.resumeTime(from: 108, afterPausing: 20, chapters: chapters, heard: heard), 106.26, accuracy: 0.011)
        // Nothing heard: the plain rewind.
        XCTAssertEqual(SmartResume.resumeTime(from: 108, afterPausing: 20, chapters: chapters, heard: nil), 106)
        // Back to the chapter's start: it stays there.
        XCTAssertEqual(SmartResume.resumeTime(from: 101, afterPausing: 3 * 60, chapters: chapters, heard: heard), 100)
    }

    func testMeterKeepsTheFilesClockAndStartsOverAtABreak() {
        var meter = LoudnessMeter(capacity: 100)
        // 1 kHz: a window is 10 frames.
        meter.beginBlock(at: 10, sampleRate: 1000, secondsPerFrame: 0.001)
        for _ in 0 ..< 25 { meter.add(0.01) }
        meter.beginBlock(at: 10.025, sampleRate: 1000, secondsPerFrame: 0.001)
        for _ in 0 ..< 15 { meter.add(0.01) }
        XCTAssertTrue(meter.isAnchored)
        XCTAssertEqual(meter.trace.times.count, 4)
        XCTAssertEqual(meter.trace.times[0], 10, accuracy: 1e-9)
        XCTAssertEqual(meter.trace.times[3], 10.03, accuracy: 1e-9)
        XCTAssertEqual(meter.trace.levels[0], -20, accuracy: 0.001)
        // A seek: what was heard before it is dropped.
        meter.beginBlock(at: 50, sampleRate: 1000, secondsPerFrame: 0.001)
        for _ in 0 ..< 10 { meter.add(0) }
        XCTAssertEqual(meter.trace.times, [50])
        XCTAssertEqual(meter.trace.levels, [-100])
    }

    func testMeterWithNoClockCountsFromZeroAndKeepsTheLatest() {
        var meter = LoudnessMeter(capacity: 100)
        meter.beginBlock(at: nil, sampleRate: 1000, secondsPerFrame: 0.001)
        for _ in 0 ..< 1500 { meter.add(0.01) }
        meter.beginBlock(at: nil, sampleRate: 1000, secondsPerFrame: 0.001)
        for _ in 0 ..< 10 { meter.add(0.01) }
        XCTAssertFalse(meter.isAnchored)
        XCTAssertLessThanOrEqual(meter.trace.times.count, 125)
        XCTAssertGreaterThanOrEqual(meter.trace.times.count, 100)
        XCTAssertEqual(meter.trace.end ?? 0, 1.51, accuracy: 1e-9)
        // Played twice as fast: each frame is two of the file's.
        var fast = LoudnessMeter()
        fast.beginBlock(at: 0, sampleRate: 1000, secondsPerFrame: 0.002)
        for _ in 0 ..< 20 { fast.add(0.01) }
        XCTAssertEqual(fast.trace.times.count, 2)
        XCTAssertEqual(fast.trace.times.last ?? 0, 0.02, accuracy: 1e-9)
        XCTAssertEqual(fast.trace.windowLength, 0.02, accuracy: 1e-9)
    }
}
