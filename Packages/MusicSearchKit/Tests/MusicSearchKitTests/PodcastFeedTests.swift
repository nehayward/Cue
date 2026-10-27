@testable import MusicSearchKit
import XCTest

final class PodcastFeedTests: XCTestCase {
    private let feedURL = URL(string: "https://example.com/show/feed.xml")!

    private let rss = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:content="http://purl.org/rss/1.0/modules/content/">
      <channel>
        <title>The Show</title>
        <link>https://example.com/show</link>
        <description><![CDATA[<p>A show about <b>things</b>.</p>]]></description>
        <itunes:author>Some One</itunes:author>
        <itunes:image href="https://example.com/show/cover.jpg"/>
        <image><url>https://example.com/show/small.jpg</url><title>The Show</title></image>
        <item>
          <title>Older</title>
          <guid isPermaLink="false">ep-1</guid>
          <pubDate>Mon, 20 Oct 2025 08:00:00 +0000</pubDate>
          <itunes:duration>45:30</itunes:duration>
          <enclosure url="https://cdn.example.com/ep1.mp3" length="123" type="audio/mpeg"/>
        </item>
        <item>
          <title><![CDATA[Newer & Better]]></title>
          <guid>ep-2</guid>
          <pubDate>Tue, 21 Oct 2025 09:30:00 GMT</pubDate>
          <itunes:duration>3725</itunes:duration>
          <itunes:image href="https://example.com/show/ep2.jpg"/>
          <description>Plain words.</description>
          <enclosure url="https://cdn.example.com/ep2.m4a?x=1" type="audio/x-m4a"/>
        </item>
        <item>
          <title>A video</title>
          <guid>ep-3</guid>
          <enclosure url="https://cdn.example.com/ep3.mp4" type="video/mp4"/>
        </item>
        <item>
          <title>No guid</title>
          <itunes:duration>1:02:03</itunes:duration>
          <enclosure url="https://cdn.example.com/ep4.mp3" type="audio/mpeg"/>
        </item>
      </channel>
    </rss>
    """

    func testChannelAndEpisodesNewestFirst() throws {
        let feed = try XCTUnwrap(PodcastFeedParser.parse(Data(rss.utf8), url: feedURL))
        XCTAssertEqual(feed.title, "The Show")
        XCTAssertEqual(feed.author, "Some One")
        XCTAssertEqual(feed.artworkURL?.absoluteString, "https://example.com/show/cover.jpg")
        XCTAssertEqual(feed.summary, "<p>A show about <b>things</b>.</p>")
        // The video is left out; one with no date goes last.
        XCTAssertEqual(feed.episodes.map(\.title), ["Newer & Better", "Older", "No guid"])

        let newest = try XCTUnwrap(feed.episodes.first)
        XCTAssertEqual(newest.duration, 3725)
        XCTAssertEqual(newest.audioURL.absoluteString, "https://cdn.example.com/ep2.m4a?x=1")
        XCTAssertEqual(newest.fileExtension, "m4a")
        XCTAssertEqual(newest.artworkURL?.absoluteString, "https://example.com/show/ep2.jpg")
        XCTAssertEqual(newest.summary, "Plain words.")
        XCTAssertEqual(newest.feedID, feed.id)
        XCTAssertEqual(newest.published, Date(timeIntervalSince1970: 1_761_039_000))

        let older = feed.episodes[1]
        XCTAssertEqual(older.duration, 2730)
        XCTAssertEqual(older.artworkURL, feed.artworkURL)
        XCTAssertEqual(older.published, Date(timeIntervalSince1970: 1_760_947_200))
        XCTAssertEqual(feed.episodes[2].duration, 3723)
    }

    func testIDsAreStable() throws {
        let first = try XCTUnwrap(PodcastFeedParser.parse(Data(rss.utf8), url: feedURL))
        let again = try XCTUnwrap(PodcastFeedParser.parse(Data(rss.utf8), url: feedURL))
        XCTAssertEqual(first.episodes.map(\.id), again.episodes.map(\.id))
        XCTAssertEqual(PodcastFeed.id(for: feedURL), first.id)
        XCTAssertTrue(first.episodes.allSatisfy { $0.id.hasPrefix(first.id + "~") && !$0.id.contains("|") })
        XCTAssertEqual(PodcastIDs.hash("a"), "af63dc4c8601ec8c")
    }

    func testMovedFeedIsFollowedWhereItSaysItIs() throws {
        let moved = rss.replacingOccurrences(of: "<title>The Show</title>", with: "<title>The Show</title><itunes:new-feed-url>https://new.example.com/feed</itunes:new-feed-url>")
        let feed = try XCTUnwrap(PodcastFeedParser.parse(Data(moved.utf8), url: feedURL))
        XCTAssertEqual(feed.url.absoluteString, "https://new.example.com/feed")
    }

    func testNotAFeed() {
        XCTAssertNil(PodcastFeedParser.parse(Data("<html><body>Hi</body></html>".utf8), url: feedURL))
        XCTAssertNil(PodcastFeedParser.parse(Data("not xml".utf8), url: feedURL))
    }

    func testAddresses() {
        XCTAssertEqual(PodcastFeeds.feedURL(from: " feeds.example.com/show ")?.absoluteString, "https://feeds.example.com/show")
        XCTAssertEqual(PodcastFeeds.feedURL(from: "feed://example.com/rss")?.absoluteString, "https://example.com/rss")
        XCTAssertEqual(PodcastFeeds.feedURL(from: "http://example.com/rss")?.absoluteString, "http://example.com/rss")
        XCTAssertNil(PodcastFeeds.feedURL(from: "not a url"))
        XCTAssertNil(PodcastFeeds.feedURL(from: "localhost"))
    }

    func testDurations() {
        XCTAssertEqual(PodcastFeedParser.duration(from: "90"), 90)
        XCTAssertEqual(PodcastFeedParser.duration(from: "01:30"), 90)
        XCTAssertEqual(PodcastFeedParser.duration(from: "1:01:30"), 3690)
        XCTAssertNil(PodcastFeedParser.duration(from: "soon"))
        XCTAssertNil(PodcastFeedParser.duration(from: "0"))
    }

    func testSpeakersStreamAndReadBack() throws {
        let feed = try XCTUnwrap(PodcastFeedParser.parse(Data(rss.utf8), url: feedURL))
        PodcastFeeds.index([feed])
        defer { PodcastFeeds.index([]) }
        let episode = feed.episodes[0]
        XCTAssertEqual(PodcastIDs.episodeID(ofPart: episode.partID), episode.id)
        XCTAssertEqual(PodcastIDs.episodeID(ofPart: episode.id), episode.id)
        XCTAssertEqual(PodcastFeeds.streamURL(for: episode.partID, fileExtension: nil, destination: .speaker), episode.audioURL)
        XCTAssertEqual(PodcastFeeds.streamURL(for: episode.id, fileExtension: nil, destination: .device), episode.audioURL)
        // A speaker's row names the audio, as set or with its entities
        // unescaped.
        XCTAssertEqual(PodcastFeeds.episodeID(forStreamURL: "https://cdn.example.com/ep2.m4a?x=1"), episode.partID)
        XCTAssertEqual(PodcastFeeds.episodeID(forStreamURL: "https://cdn.example.com/ep2.m4a?x=1".replacingOccurrences(of: "&", with: "&amp;")), episode.partID)
        XCTAssertTrue(PodcastFeeds.isStreamURL("https://cdn.example.com/ep1.mp3"))
        XCTAssertFalse(PodcastFeeds.isStreamURL("https://cdn.example.com/other.mp3"))
    }
}
