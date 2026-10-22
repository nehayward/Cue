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

    func testNextAndPreviousChapter() {
        let chapters = [
            AudiobookChapter(id: 0, title: "One", start: 0, end: 600),
            AudiobookChapter(id: 1, title: "Two", start: 600, end: 1200),
            AudiobookChapter(id: 2, title: "Three", start: 1200, end: 1800)
        ]
        XCTAssertEqual(chapters.chapter(after: 10)?.id, 1)
        XCTAssertEqual(chapters.chapter(after: 700)?.id, 2)
        XCTAssertNil(chapters.chapter(after: 1300))
        // Just short of a mark is already that chapter, so Next goes on
        // past it rather than to it again.
        XCTAssertEqual(chapters.chapter(after: 599.9)?.id, 2)

        // A few seconds in, Previous goes back to the chapter's start…
        XCTAssertEqual(chapters.previousChapterStart(from: 700), 600)
        // …and right at it, to the one before.
        XCTAssertEqual(chapters.previousChapterStart(from: 601), 0)
        XCTAssertEqual(chapters.previousChapterStart(from: 2), 0)
        XCTAssertNil([AudiobookChapter]().previousChapterStart(from: 10))
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

    func testResumeGoesBackFurtherTheLongerItRested() {
        let left = Date(timeIntervalSince1970: 1_000_000)
        let progress = AudiobookProgress(position: 1000, duration: 3600, updatedAt: left)
        XCTAssertEqual(progress.resumePosition(at: left.addingTimeInterval(5), chapters: []), 999)
        XCTAssertEqual(progress.resumePosition(at: left.addingTimeInterval(30 * 60), chapters: []), 995)
        XCTAssertEqual(progress.resumePosition(at: left.addingTimeInterval(3 * 24 * 60 * 60), chapters: []), 985)
        // The first half minute is a sample, not a start.
        XCTAssertEqual(AudiobookProgress(position: 20, duration: 3600).resumePosition, 0)
    }

    func testSmartResumeStopsAtTheChapterStart() {
        let chapters = [
            AudiobookChapter(id: 0, title: "One", start: 0, end: 998),
            AudiobookChapter(id: 1, title: "Two", start: 998, end: 2000),
        ]
        XCTAssertEqual(SmartResume.resumeTime(from: 500, afterPausing: 2 * 60 * 60, chapters: chapters), 490)
        XCTAssertEqual(SmartResume.resumeTime(from: 1000, afterPausing: 2 * 60 * 60, chapters: chapters), 998)
        // Just short of the next chapter: it stays put, never goes forward.
        XCTAssertEqual(SmartResume.resumeTime(from: 997.9, afterPausing: 2 * 60 * 60, chapters: chapters), 997.9)
        XCTAssertEqual(SmartResume.resumeTime(from: 3, afterPausing: 2 * 60 * 60), 0)
    }

    func testSmartResumeRewindGrowsWithThePause() {
        XCTAssertEqual(SmartResume.rewind(afterPausing: 2), 1)
        XCTAssertEqual(SmartResume.rewind(afterPausing: 30), 2)
        XCTAssertEqual(SmartResume.rewind(afterPausing: 3 * 60), 3)
        XCTAssertEqual(SmartResume.rewind(afterPausing: 20 * 60), 5)
        XCTAssertEqual(SmartResume.rewind(afterPausing: 8 * 60 * 60), 10)
        XCTAssertEqual(SmartResume.rewind(afterPausing: 3 * 24 * 60 * 60), 15)
    }

    func testNewerWins() {
        let old = AudiobookProgress(position: 100, duration: 3600, updatedAt: Date(timeIntervalSince1970: 1000))
        let new = AudiobookProgress(position: 50, duration: 3600, updatedAt: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(AudiobookProgress.newer(old, new), new)
        XCTAssertEqual(AudiobookProgress.newer(new, old), new)
        XCTAssertEqual(AudiobookProgress.newer(nil, old), old)
        XCTAssertNil(AudiobookProgress.newer(nil, nil))
    }

    func testThisDevicesPlaceUnlessTheServersIsClearlyNewer() {
        // Plex, a few seconds after this device's own play: the first file
        // counted played, read as the start of the second.
        let device = AudiobookProgress(position: 600, duration: 58_254, updatedAt: Date(timeIntervalSince1970: 1000))
        let plexAfter = AudiobookProgress(position: 2224, duration: 58_254, updatedAt: Date(timeIntervalSince1970: 1010))
        XCTAssertEqual(AudiobookProgress.preferring(local: device, server: plexAfter), device)
        // Another player, an hour later.
        let elsewhere = AudiobookProgress(position: 9000, duration: 58_254, updatedAt: Date(timeIntervalSince1970: 4600))
        XCTAssertEqual(AudiobookProgress.preferring(local: device, server: elsewhere), elsewhere)
        XCTAssertEqual(AudiobookProgress.preferring(local: nil, server: elsewhere), elsewhere)
        XCTAssertEqual(AudiobookProgress.preferring(local: device, server: nil), device)
    }
}
