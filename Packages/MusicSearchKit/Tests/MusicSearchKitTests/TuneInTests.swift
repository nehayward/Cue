import XCTest
@testable import MusicSearchKit

final class TuneInTests: XCTestCase {
    func testLocalBrowsePageParsesIntoBandGroups() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "tuneInLocalBrowse", withExtension: "xml"))
        let items = TuneInParser().parseBrowse(xmlData: try Data(contentsOf: url))

        // A local page is FM and AM blocks, each holding stations.
        XCTAssertGreaterThanOrEqual(items.count, 2)
        guard case let .group(fm) = items[0] else { return XCTFail("Expected the FM group first, got \(items[0])") }
        XCTAssertEqual(fm.title, "FM")
        XCTAssertFalse(fm.items.isEmpty)

        guard case let .station(station) = try XCTUnwrap(fm.items.first) else { return XCTFail("Expected a station") }
        XCTAssertEqual(station.id, "s31656")
        XCTAssertEqual(station.title, "88.1 | KBCU (Jazz)")
        // No current track on a browse page: the tagline is the caption.
        XCTAssertEqual(station.stationInfo?.song, "All about kbcU.")
        XCTAssertEqual(station.imageURL?.absoluteString, "http://cdn-profiles.tunein.com/s31656/images/logod.png?t=1")
    }

    func testBrowsePageKeepsLinksAndStationsAndDropsShows() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="1"><head><title>Music</title><status>200</status></head><body>
        <outline type="link" text="Country" URL="http://opml.radiotime.com/Browse.ashx?id=c57940" guide_id="c57940"/>
        <outline type="audio" text="WBGO" URL="http://opml.radiotime.com/Tune.ashx?id=s27437" guide_id="s27437" subtext="Jazz 88.3" item="station" current_track="The Dave Koz Radio Show" image="http://cdn-profiles.tunein.com/s27437/images/logoq.jpg"/>
        <outline type="audio" text="Some Podcast Episode" URL="http://opml.radiotime.com/Tune.ashx?id=t1" guide_id="t1" item="topic"/>
        <outline type="link" text="No id" URL="http://opml.radiotime.com/Browse.ashx?c=local&amp;offset=20" key="more"/>
        </body></opml>
        """
        let items = TuneInParser().parseBrowse(xmlData: Data(xml.utf8))

        XCTAssertEqual(items.count, 3)
        guard case let .link(country) = items[0] else { return XCTFail("Expected a link first") }
        XCTAssertEqual(country.title, "Country")
        XCTAssertEqual(country.guideID, "c57940")
        XCTAssertEqual(country.url.scheme, "https")

        guard case let .station(station) = items[1] else { return XCTFail("Expected a station second") }
        XCTAssertEqual(station.id, "s27437")
        XCTAssertEqual(station.stationInfo?.song, "The Dave Koz Radio Show")

        guard case let .link(more) = items[2] else { return XCTFail("Expected the id-less link last") }
        XCTAssertNil(more.guideID)
        XCTAssertEqual(more.url.absoluteString, "https://opml.radiotime.com/Browse.ashx?c=local&offset=20")
    }

    func testBrowsePageURLs() {
        XCTAssertEqual(TuneInBrowsePage.local.url.absoluteString, "https://opml.radiotime.com/Browse.ashx?c=local")
        XCTAssertEqual(TuneInBrowsePage.byLocation.url.absoluteString, "https://opml.radiotime.com/Browse.ashx?id=r0")
        XCTAssertEqual(TuneInBrowsePage.id("g22").url.absoluteString, "https://opml.radiotime.com/Browse.ashx?id=g22")
    }

    func testStreamResponsePrefersPlainAudioThenReliability() throws {
        let json = """
        { "head": { "status": "200" }, "body": [
          { "element": "audio", "url": "https://a.example/live.m3u8", "reliability": 100, "bitrate": 128, "media_type": "hls", "is_direct": true },
          { "element": "audio", "url": "http://b.example:8000/stream", "reliability": 90, "bitrate": 230, "media_type": "mp3", "is_direct": true },
          { "element": "audio", "url": "http://c.example/stream.aac", "reliability": 98, "bitrate": 96, "media_type": "aac", "is_direct": true }
        ] }
        """
        let streams = try JSONDecoder().decode(TuneInStreamResponse.self, from: Data(json.utf8)).body
        XCTAssertEqual(streams.count, 3)
        XCTAssertTrue(streams[0].isHLS)
        XCTAssertEqual(streams.preferred?.url.absoluteString, "http://c.example/stream.aac")
        XCTAssertNil([TuneInStream]().preferred)
    }

    func testSearchResultsStillParseFlat() {
        let xml = """
        <opml version="1"><body>
        <outline type="audio" text="KEXP" guide_id="s1" playing="Now: Song" current_track="Song" image="http://x/logoq.png"/>
        </body></opml>
        """
        let stations = TuneInParser().parseStations(xmlData: Data(xml.utf8))
        XCTAssertEqual(stations.count, 1)
        XCTAssertEqual(stations.first?.stationInfo?.song, "Now: Song")
        XCTAssertEqual(stations.first?.imageURL?.absoluteString, "http://x/logod.png")
    }
}
