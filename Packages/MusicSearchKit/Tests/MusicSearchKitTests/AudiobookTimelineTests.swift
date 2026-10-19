@testable import MusicSearchKit
import XCTest

final class AudiobookTimelineTests: XCTestCase {
    private let timeline = AudiobookTimeline(partDurations: [600, 300, 900])

    func testDurationAndStarts() {
        XCTAssertEqual(timeline.duration, 1800)
        XCTAssertEqual(timeline.start(ofPart: 0), 0)
        XCTAssertEqual(timeline.start(ofPart: 1), 600)
        XCTAssertEqual(timeline.start(ofPart: 2), 900)
        XCTAssertEqual(timeline.start(ofPart: 3), 1800)
    }

    func testLocationInsideAFile() {
        let location = timeline.location(at: 750)
        XCTAssertEqual(location.part, 1)
        XCTAssertEqual(location.offset, 150, accuracy: 0.001)
    }

    func testABoundaryIsTheStartOfTheLaterFile() {
        let location = timeline.location(at: 600)
        XCTAssertEqual(location.part, 1)
        XCTAssertEqual(location.offset, 0)
    }

    func testOutOfRangeTimesClamp() {
        XCTAssertEqual(timeline.location(at: -10).part, 0)
        XCTAssertEqual(timeline.location(at: -10).offset, 0)
        let end = timeline.location(at: 5000)
        XCTAssertEqual(end.part, 2)
        XCTAssertEqual(end.offset, 900)
    }

    func testTimeIsTheInverseOfLocation() {
        for time in stride(from: 0.0, to: 1800, by: 37.5) {
            let location = timeline.location(at: time)
            XCTAssertEqual(timeline.time(part: location.part, offset: location.offset), time, accuracy: 0.001)
        }
    }

    func testTimeHoldsTheOffsetToTheFile() {
        XCTAssertEqual(timeline.time(part: 1, offset: 1000), 900)
        XCTAssertEqual(timeline.time(part: -1, offset: 10), 0)
        XCTAssertEqual(timeline.time(part: 9, offset: 10), 1800)
    }

    func testEmptyAndBrokenLengths() {
        let empty = AudiobookTimeline(partDurations: [])
        XCTAssertEqual(empty.duration, 0)
        XCTAssertEqual(empty.location(at: 10).part, 0)
        let broken = AudiobookTimeline(partDurations: [.nan, -5, 60])
        XCTAssertEqual(broken.duration, 60)
        XCTAssertEqual(broken.location(at: 10).part, 2)
    }

    func testChapterAtTime() {
        let chapters = [
            AudiobookChapter(id: 0, title: "Opening Credits", start: 0, end: 30),
            AudiobookChapter(id: 1, title: "One", start: 30, end: 1000),
            AudiobookChapter(id: 2, title: "Two", start: 1000, end: 1800)
        ]
        XCTAssertEqual(chapters.chapter(at: 0)?.id, 0)
        XCTAssertEqual(chapters.chapter(at: 500)?.id, 1)
        XCTAssertEqual(chapters.chapter(at: 1000)?.id, 2)
        // A seek that lands just short of a chapter mark is in that chapter.
        XCTAssertEqual(chapters.chapter(at: 999.9)?.id, 2)
        XCTAssertEqual(chapters.chapter(at: 99_999)?.id, 2)
        XCTAssertNil([AudiobookChapter]().chapter(at: 10))
    }

    func testChaptersPerFile() {
        let chapters = [AudiobookChapter].perPart(titles: ["Part 1", "Part 2", "Part 3", "Extra"], timeline: timeline)
        XCTAssertEqual(chapters.map(\.title), ["Part 1", "Part 2", "Part 3"])
        XCTAssertEqual(chapters.map(\.start), [0, 600, 900])
        XCTAssertEqual(chapters.map(\.end), [600, 900, 1800])
    }
}

final class AudiobookProgressTests: XCTestCase {
    func testFractionAndRemaining() {
        let progress = AudiobookProgress(position: 900, duration: 3600)
        XCTAssertEqual(progress.fraction ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertEqual(progress.remaining, 2700)
        XCTAssertNil(AudiobookProgress(position: 10, duration: 0).fraction)
    }

    func testFinishedIsAllOfIt() {
        let progress = AudiobookProgress(position: 100, duration: 3600, isFinished: true)
        XCTAssertEqual(progress.fraction, 1)
        XCTAssertEqual(progress.remaining, 0)
        XCTAssertFalse(progress.isStarted)
        XCTAssertEqual(progress.resumePosition, 0)
    }

    func testResumeRewindsAFewSeconds() {
        XCTAssertEqual(AudiobookProgress(position: 1000, duration: 3600).resumePosition, 995)
        // The first half minute is a sample, not a start.
        XCTAssertEqual(AudiobookProgress(position: 20, duration: 3600).resumePosition, 0)
    }

    func testNewerWins() {
        let old = AudiobookProgress(position: 100, duration: 3600, updatedAt: Date(timeIntervalSince1970: 1000))
        let new = AudiobookProgress(position: 50, duration: 3600, updatedAt: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(AudiobookProgress.newer(old, new), new)
        XCTAssertEqual(AudiobookProgress.newer(new, old), new)
        XCTAssertEqual(AudiobookProgress.newer(nil, old), old)
        XCTAssertNil(AudiobookProgress.newer(nil, nil))
    }
}
