@testable import MusicSearchKit
import XCTest

final class PlexAudiobookTests: XCTestCase {
    /// A book's files as `/library/metadata/<book>/children` lists them,
    /// trimmed to what Cue reads.
    private func parts(_ json: String) throws -> [PlexMetadata] {
        let container = try JSONDecoder().decode(PlexContainer<PlexMetadataList>.self, from: Data(json.utf8))
        return container.mediaContainer.metadata ?? []
    }

    private func track(_ key: String, title: String, duration: Int, viewOffset: Int? = nil, viewCount: Int? = nil, lastViewedAt: Int? = nil, chapters: String? = nil) -> String {
        var fields = [
            "\"ratingKey\": \"\(key)\"",
            "\"key\": \"/library/metadata/\(key)\"",
            "\"guid\": \"plex://track/\(key)\"",
            "\"type\": \"track\"",
            "\"title\": \"\(title)\"",
            "\"summary\": \"\"",
            "\"duration\": \(duration)"
        ]
        if let viewOffset { fields.append("\"viewOffset\": \(viewOffset)") }
        if let viewCount { fields.append("\"viewCount\": \(viewCount)") }
        if let lastViewedAt { fields.append("\"lastViewedAt\": \(lastViewedAt)") }
        if let chapters { fields.append("\"Chapter\": \(chapters)") }
        return "{\(fields.joined(separator: ","))}"
    }

    private func container(_ tracks: [String]) -> String {
        "{\"MediaContainer\": {\"size\": \(tracks.count), \"Metadata\": [\(tracks.joined(separator: ","))]}}"
    }

    func testDecodesResumeAndChapterMarks() throws {
        let chapters = """
        [{"id": 1, "index": 1, "tag": "Opening Credits", "startTimeOffset": 0, "endTimeOffset": 25000},
         {"id": 2, "index": 2, "tag": "Chapter One", "startTimeOffset": 25000, "endTimeOffset": 1800000}]
        """
        let parts = try parts(container([track("11", title: "The Book", duration: 1_800_000, viewOffset: 600_000, lastViewedAt: 1_700_000_000, chapters: chapters)]))
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].viewOffset, 600_000)
        XCTAssertEqual(parts[0].chapters?.count, 2)

        let timeline = PlexAudiobook.timeline(parts: parts)
        XCTAssertEqual(timeline.duration, 1800)
        let marks = PlexAudiobook.chapters(parts: parts, timeline: timeline)
        XCTAssertEqual(marks.map(\.title), ["Opening Credits", "Chapter One"])
        XCTAssertEqual(marks.map(\.start), [0, 25])
        XCTAssertEqual(marks.map(\.end), [25, 1800])

        let progress = try XCTUnwrap(PlexAudiobook.progress(parts: parts, timeline: timeline))
        XCTAssertEqual(progress.position, 600)
        XCTAssertFalse(progress.isFinished)
        XCTAssertEqual(progress.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testAFilePerChapter() throws {
        let parts = try parts(container([
            track("1", title: "Chapter 1", duration: 600_000, viewCount: 1, lastViewedAt: 100),
            track("2", title: "Chapter 2", duration: 600_000, viewCount: 1, lastViewedAt: 200),
            track("3", title: "Chapter 3", duration: 600_000)
        ]))
        let timeline = PlexAudiobook.timeline(parts: parts)
        XCTAssertEqual(PlexAudiobook.chapters(parts: parts, timeline: timeline).map(\.title), ["Chapter 1", "Chapter 2", "Chapter 3"])
        // The second file was played through last: the book resumes at the
        // top of the third.
        let progress = try XCTUnwrap(PlexAudiobook.progress(parts: parts, timeline: timeline))
        XCTAssertEqual(progress.position, 1200)
    }

    func testTheFileListenedToLastWins() throws {
        let parts = try parts(container([
            track("1", title: "One", duration: 600_000, viewOffset: 50_000, lastViewedAt: 100),
            track("2", title: "Two", duration: 600_000, viewOffset: 120_000, lastViewedAt: 300),
            track("3", title: "Three", duration: 600_000)
        ]))
        let progress = try XCTUnwrap(PlexAudiobook.progress(parts: parts, timeline: PlexAudiobook.timeline(parts: parts)))
        XCTAssertEqual(progress.position, 720)
    }

    func testAPartwayFileWithNoDate() throws {
        let parts = try parts(container([
            track("1", title: "One", duration: 600_000),
            track("2", title: "Two", duration: 600_000, viewOffset: 30_000)
        ]))
        let progress = try XCTUnwrap(PlexAudiobook.progress(parts: parts, timeline: PlexAudiobook.timeline(parts: parts)))
        XCTAssertEqual(progress.position, 630)
    }

    func testNeverStartedAndFinished() throws {
        let fresh = try parts(container([track("1", title: "One", duration: 600_000)]))
        XCTAssertNil(PlexAudiobook.progress(parts: fresh, timeline: PlexAudiobook.timeline(parts: fresh)))

        let done = try parts(container([
            track("1", title: "One", duration: 600_000, viewCount: 1, lastViewedAt: 100),
            track("2", title: "Two", duration: 600_000, viewCount: 2, lastViewedAt: 200)
        ]))
        let progress = try XCTUnwrap(PlexAudiobook.progress(parts: done, timeline: PlexAudiobook.timeline(parts: done)))
        XCTAssertTrue(progress.isFinished)
        XCTAssertEqual(progress.position, 1200)
    }

    func testBookListDecodesWithoutAnIndex() throws {
        let json = """
        {"MediaContainer": {"size": 1, "totalSize": 1, "Metadata": [
          {"ratingKey": "500", "title": "Project Hail Mary", "parentTitle": "Andy Weir",
           "leafCount": 1, "viewedLeafCount": 0, "Genre": [{"tag": "Audiobook"}, {"tag": "Science Fiction"}]}
        ]}}
        """
        let container = try JSONDecoder().decode(PlexContainer<PlexAudiobookContainer>.self, from: Data(json.utf8))
        let book = try XCTUnwrap(container.mediaContainer.metadata?.first)
        XCTAssertEqual(book.title, "Project Hail Mary")
        XCTAssertEqual(book.parentTitle, "Andy Weir")
        XCTAssertTrue(book.hasAudiobookGenre)
    }
}
