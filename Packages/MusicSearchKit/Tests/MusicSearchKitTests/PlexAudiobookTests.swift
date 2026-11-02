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

    func testChapterLookupReadsOnlyTheMarks() throws {
        // A track's full metadata, with fields the lookup doesn't model (and
        // a summary-less, guid-less item that wouldn't decode as metadata).
        let json = """
        {"MediaContainer": {"size": 1, "Metadata": [{"ratingKey": "11", "type": "track",
          "Media": [{"id": 5, "Part": [{"id": 9, "Stream": [{"id": 1, "streamType": 2}]}]}],
          "Chapter": [{"id": 1, "tag": "Prologue", "startTimeOffset": 0, "endTimeOffset": 60000},
                      {"id": 2, "tag": "One", "startTimeOffset": 60000}]}]}}
        """
        let lookup = try JSONDecoder().decode(PlexContainer<PlexChapterLookup>.self, from: Data(json.utf8))
        let chapters = try XCTUnwrap(lookup.mediaContainer.metadata?.first?.chapters)
        let marks = PlexAudiobook.chapterMarks(chapters)
        XCTAssertEqual(marks, [
            AudiobookChapterMark(title: "Prologue", start: 0, end: 60),
            AudiobookChapterMark(title: "One", start: 60)
        ])
    }

    func testMarksReadOnTheirOwnWin() throws {
        let parts = try parts(container([
            track("1", title: "Disc 1", duration: 600_000),
            track("2", title: "Disc 2", duration: 600_000)
        ]))
        let timeline = PlexAudiobook.timeline(parts: parts)
        let chapters = PlexAudiobook.chapters(
            parts: parts,
            marks: ["2": [AudiobookChapterMark(title: "Four", start: 0), AudiobookChapterMark(title: nil, start: 300)]],
            timeline: timeline
        )
        // The first file has no marks and stands as one chapter; the
        // second's are laid after it, an untitled one numbered in the book.
        XCTAssertEqual(chapters.map(\.title), ["Disc 1", "Four", "Chapter 3"])
        XCTAssertEqual(chapters.map(\.start), [0, 600, 900])
        XCTAssertEqual(chapters.map(\.end), [600, 900, 1200])
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

    func testAFilePlayedDoesNotMoveThisDevicePastIt() throws {
        // Project Hail Mary, Store track progress off: this device left the
        // first file 10 minutes in, and its report on leaving it, an hour
        // later, had Plex count it played.
        let parts = try parts(container([
            track("1", title: "01", duration: 2_224_979, viewCount: 10, lastViewedAt: 4600),
            track("2", title: "02", duration: 1_721_521),
            track("3", title: "03", duration: 2_241_253)
        ]))
        let timeline = PlexAudiobook.timeline(parts: parts)
        let plex = try XCTUnwrap(PlexAudiobook.progress(parts: parts, timeline: timeline))
        XCTAssertEqual(plex.position, timeline.start(ofPart: 1), accuracy: 0.001)
        let device = AudiobookProgress(position: 600, duration: timeline.duration, updatedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(PlexAudiobook.preferring(local: device, server: plex, timeline: timeline), device)
        // Near the end of that file too: still this device's.
        let late = AudiobookProgress(position: 2200, duration: timeline.duration, updatedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(PlexAudiobook.preferring(local: late, server: plex, timeline: timeline), late)
        // With no reading here, Plex's is all there is.
        XCTAssertEqual(PlexAudiobook.preferring(local: nil, server: plex, timeline: timeline), plex)
    }

    func testLaterFilesPlayedElsewhereWin() throws {
        let parts = try parts(container([
            track("1", title: "01", duration: 600_000, viewCount: 1, lastViewedAt: 3000),
            track("2", title: "02", duration: 600_000, viewCount: 1, lastViewedAt: 4600),
            track("3", title: "03", duration: 600_000)
        ]))
        let timeline = PlexAudiobook.timeline(parts: parts)
        let plex = try XCTUnwrap(PlexAudiobook.progress(parts: parts, timeline: timeline))
        let device = AudiobookProgress(position: 300, duration: timeline.duration, updatedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(PlexAudiobook.preferring(local: device, server: plex, timeline: timeline), plex)
        // Not when this device's reading is the newer.
        let recent = AudiobookProgress(position: 300, duration: timeline.duration, updatedAt: Date(timeIntervalSince1970: 5000))
        XCTAssertEqual(PlexAudiobook.preferring(local: recent, server: plex, timeline: timeline), recent)
    }

    func testAOneFileBookCountedPlayedIsNotFinished() throws {
        // Counted played on leaving it in the last chapters: Plex calls the
        // whole book finished, which would start it over.
        let parts = try parts(container([track("1", title: "Fellowship", duration: 81_500_734, viewCount: 1, lastViewedAt: 4600)]))
        let timeline = PlexAudiobook.timeline(parts: parts)
        let plex = try XCTUnwrap(PlexAudiobook.progress(parts: parts, timeline: timeline))
        XCTAssertTrue(plex.isFinished)
        let device = AudiobookProgress(position: 75_000, duration: timeline.duration, updatedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(PlexAudiobook.preferring(local: device, server: plex, timeline: timeline), device)
    }

    func testAPlaceInAFileGoesByDate() throws {
        // Store track progress on: a place, which a newer reading moves.
        let parts = try parts(container([
            track("1", title: "01", duration: 600_000, viewCount: 1, lastViewedAt: 3000),
            track("2", title: "02", duration: 600_000, viewOffset: 120_000, lastViewedAt: 4600)
        ]))
        let timeline = PlexAudiobook.timeline(parts: parts)
        let plex = try XCTUnwrap(PlexAudiobook.progress(parts: parts, timeline: timeline))
        XCTAssertEqual(plex.position, 720)
        let device = AudiobookProgress(position: 650, duration: timeline.duration, updatedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(PlexAudiobook.preferring(local: device, server: plex, timeline: timeline), plex)
        let recent = AudiobookProgress(position: 650, duration: timeline.duration, updatedAt: Date(timeIntervalSince1970: 4630))
        XCTAssertEqual(PlexAudiobook.preferring(local: recent, server: plex, timeline: timeline), recent)
    }

    func testAFileGoesOnlyOntoItsOwnServersConnection() throws {
        let remote = try XCTUnwrap(URL(string: "https://75-172-51-158.abc123.plex.direct:20891/library/parts/9582/1/file.mp3?X-Plex-Token=t"))
        let local = try XCTUnwrap(URL(string: "https://192-168-5-166.abc123.plex.direct:32400"))
        let other = try XCTUnwrap(URL(string: "https://10-0-0-2.def456.plex.direct:32400"))
        XCTAssertTrue(PlexAPI.isSameServer(remote, local))
        XCTAssertFalse(PlexAPI.isSameServer(remote, other))
        XCTAssertTrue(PlexAPI.isSameServer(remote, remote))
        XCTAssertFalse(PlexAPI.isSameServer(remote, try XCTUnwrap(URL(string: "http://192.168.5.166:32400"))))
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
