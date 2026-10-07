import XCTest
@testable import SonosKit

final class DownloadChecksTests: XCTestCase {

    private let conversion = URL(string: "https://192-168-5-166.abc.plex.direct:32400/music/:/transcode/universal/start.mp3?path=/library/metadata/2163&musicBitrate=256&session=cue-2163&X-Plex-Client-Identifier=Cue&X-Plex-Token=t")!
    private let original = URL(string: "https://192-168-5-166.abc.plex.direct:32400/library/parts/4729/1714957943/file.flac?X-Plex-Token=t")!

    // MARK: Cut-short conversions

    func testAConversionMustWeighHalfItsLengthAtItsBitrate() {
        // 200 s at 256 kbps is 6.4 MB; half of that is the floor.
        XCTAssertEqual(DownloadChecks.minimumConvertedSize(seconds: 200, url: conversion), 3_200_000)
    }

    func testThe64KBPlexLeftOfAnEndedTranscodeIsCaught() {
        let minimum = DownloadChecks.minimumConvertedSize(seconds: 209, url: conversion)
        XCTAssertNotNil(minimum)
        XCTAssertLessThan(Int64(65_536), minimum!)
        // A whole song at 256 kbps (as Plex sent "Cool") passes.
        XCTAssertGreaterThan(Int64(5_978_300), minimum!)
    }

    func testSubsonicsBitrateParameterCountsToo() {
        let subsonic = URL(string: "https://music.local/rest/stream?id=1&format=mp3&maxBitRate=128")!
        XCTAssertEqual(DownloadChecks.minimumConvertedSize(seconds: 100, url: subsonic), 800_000)
    }

    func testTheOriginalFileAndUnknownLengthsAreNotJudged() {
        XCTAssertNil(DownloadChecks.minimumConvertedSize(seconds: 200, url: original))
        XCTAssertNil(DownloadChecks.minimumConvertedSize(seconds: nil, url: conversion))
        XCTAssertNil(DownloadChecks.minimumConvertedSize(seconds: 3, url: conversion))
    }

    // MARK: Plex clients

    func testAConversionIsAskedForUnderTheGivenClientAndNothingElseChanges() {
        let moved = DownloadChecks.plexConversion(conversion, client: "Cue-Download-2")
        XCTAssertEqual(DownloadChecks.plexClient(in: moved), "Cue-Download-2")
        let before = URLComponents(url: conversion, resolvingAgainstBaseURL: false)!.queryItems!.filter { $0.name != "X-Plex-Client-Identifier" }
        let after = URLComponents(url: moved, resolvingAgainstBaseURL: false)!.queryItems!.filter { $0.name != "X-Plex-Client-Identifier" }
        XCTAssertEqual(before, after)
        XCTAssertEqual(moved.path, conversion.path)
    }

    func testTheOriginalFileKeepsItsURL() {
        XCTAssertEqual(DownloadChecks.plexConversion(original, client: "Cue-Download"), original)
        XCTAssertNil(DownloadChecks.plexClient(in: original))
    }
}

final class PagedListTests: XCTestCase {

    /// A server holding `count` items, `pageSize` a page, that fails the
    /// pages at the offsets in `failing` and any page past the end.
    private func server(count: Int, pageSize: Int = 3, total: Bool = true, failing: Set<Int> = []) -> (Int) async -> (items: [Int], total: Int?)? {
        { offset in
            guard !failing.contains(offset), offset < count || count == 0 else { return nil }
            let items = Array(offset ..< min(offset + pageSize, count))
            return (items, total ? count : nil)
        }
    }

    func testEveryPageIsFetchedUpToTheTotal() async {
        let items = await PagedList.all(pageSize: 3, page: server(count: 8))
        XCTAssertEqual(items, Array(0 ..< 8))
    }

    func testAnExactMultipleStopsAtTheTotalWithoutAskingPastTheEnd() async {
        var asked: [Int] = []
        let items = await PagedList.all(pageSize: 3) { offset -> (items: [Int], total: Int?)? in
            asked.append(offset)
            return await self.server(count: 6)(offset)
        }
        XCTAssertEqual(items, Array(0 ..< 6))
        XCTAssertEqual(asked, [0, 3])
    }

    func testAPageThatFailsPartWayFailsTheLot() async {
        let items = await PagedList.all(pageSize: 3, page: server(count: 8, failing: [3]))
        XCTAssertNil(items)
    }

    func testAFirstPageThatFailsFailsTheLot() async {
        let items = await PagedList.all(pageSize: 3, page: server(count: 8, failing: [0]))
        XCTAssertNil(items)
    }

    func testWithNoTotalAShortPageIsTheEnd() async {
        let items = await PagedList.all(pageSize: 3, page: server(count: 7, total: false))
        XCTAssertEqual(items, Array(0 ..< 7))
    }

    func testThePageThatReachesTheTotalIsTheLastAsked() async {
        // A page past the end would fail; it's never asked for.
        let items = await PagedList.all(pageSize: 3) { offset -> (items: [Int], total: Int?)? in
            offset >= 6 ? nil : (Array(offset ..< offset + 3), 5)
        }
        XCTAssertEqual(items, Array(0 ..< 6))
    }

    func testAnEmptyPageIsTheEnd() async {
        let items = await PagedList.all(pageSize: 3) { offset -> (items: [Int], total: Int?)? in
            offset == 0 ? ([1, 2, 3], 10) : ([], 10)
        }
        XCTAssertEqual(items, [1, 2, 3])
    }

    func testAServerThatIgnoresTheOffsetStopsAtTheBound() async {
        let items = await PagedList.all(pageSize: 3, maxPages: 4) { _ -> (items: [Int], total: Int?)? in
            ([1, 2, 3], nil)
        }
        XCTAssertEqual(items?.count, 12)
    }
}
