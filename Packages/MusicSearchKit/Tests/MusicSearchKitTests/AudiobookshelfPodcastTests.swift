@testable import MusicSearchKit
import XCTest

final class AudiobookshelfPodcastTests: XCTestCase {
    // MARK: Keys

    func testMediaKeyRoundTrip() {
        let book = AudiobookshelfMediaKey("li_1")
        XCTAssertEqual(book.itemID, "li_1")
        XCTAssertNil(book.episodeID)
        XCTAssertFalse(book.isEpisode)
        XCTAssertEqual(book.pathSuffix, "li_1")

        let episode = AudiobookshelfMediaKey(itemID: "li_2", episodeID: "ep_9")
        XCTAssertEqual(episode.string, "li_2~ep_9")
        XCTAssertEqual(AudiobookshelfMediaKey(episode.string), episode)
        XCTAssertTrue(episode.isEpisode)
        XCTAssertEqual(episode.pathSuffix, "li_2/ep_9")

        // An empty episode is no episode.
        XCTAssertEqual(AudiobookshelfMediaKey(itemID: "li_3", episodeID: ""), AudiobookshelfMediaKey("li_3"))
    }

    func testEpisodeFileAndCoverAreThePodcasts() throws {
        let base = try XCTUnwrap(URL(string: "https://example.com/abs"))
        XCTAssertEqual(
            AudiobookshelfURLs.fileURL(base: base, itemID: "li_2~ep_9", fileID: "77", token: "t", fileExtension: "mp3")?.absoluteString,
            "https://example.com/abs/api/items/li_2/file/77?token=t&ext=.mp3"
        )
        XCTAssertEqual(
            AudiobookshelfURLs.coverURL(base: base, itemID: "li_2~ep_9")?.absoluteString,
            "https://example.com/abs/api/items/li_2/cover?format=jpeg"
        )
    }

    func testEpisodePartMatchesItsFileURL() {
        // The book's part names the episode; a speaker's file URL only the
        // podcast and the file.
        let part = AudiobookshelfPartID(itemID: "li_2~ep_9", index: 1, fileID: "77")
        XCTAssertEqual(AudiobookshelfPartID(part.string), part)
        XCTAssertTrue(part.isSameFile(as: AudiobookshelfPartID(itemID: "li_2", index: 0, fileID: "77")))
        XCTAssertFalse(part.isSameFile(as: AudiobookshelfPartID(itemID: "li_2", index: 0, fileID: "78")))
        // By session index, the episode itself must match.
        XCTAssertTrue(part.isSameFile(as: AudiobookshelfPartID(itemID: "li_2~ep_9", index: 1, fileID: "-")))
        XCTAssertFalse(part.isSameFile(as: AudiobookshelfPartID(itemID: "li_2~ep_8", index: 1, fileID: "-")))
    }

    // MARK: Episodes as items

    private let podcastJSON = """
    {
      "id": "li_2",
      "libraryId": "lib_p",
      "mediaType": "podcast",
      "media": {
        "metadata": { "title": "The Show", "author": "Someone", "description": "<p>About it</p>" },
        "episodes": [
          {
            "id": "ep_old", "libraryItemId": "li_2", "title": "First", "publishedAt": 1700000000000,
            "audioFile": { "index": 1, "ino": "70", "duration": 1800.5, "mimeType": "audio/mpeg", "codec": "mp3",
                           "metadata": { "filename": "first.mp3", "ext": ".mp3", "size": 123 } }
          },
          {
            "id": "ep_new", "libraryItemId": "li_2", "title": "Second", "publishedAt": 1760000000000, "duration": 2400,
            "chapters": [ { "id": 0, "start": 0, "end": 1200, "title": "Intro" }, { "id": 1, "start": 1200, "end": 2400, "title": "Talk" } ],
            "audioTrack": { "index": 1, "startOffset": 0, "duration": 2400, "title": "second.m4a", "contentUrl": "/api/items/li_2/file/71",
                            "mimeType": "audio/mp4", "codec": "aac", "metadata": { "filename": "second.m4a", "ext": ".m4a" } }
          }
        ]
      }
    }
    """

    func testEpisodesNewestFirstAsBooksOfOneFile() throws {
        let podcast = try JSONDecoder().decode(AudiobookshelfItem.self, from: Data(podcastJSON.utf8))
        XCTAssertTrue(podcast.isPodcast)
        XCTAssertFalse(podcast.hasAudio)
        XCTAssertEqual(podcast.podcastTitle, "The Show")

        let episodes = AudiobookshelfAPI.shared.episodes(of: podcast)
        XCTAssertEqual(episodes.map(\.id), ["li_2~ep_new", "li_2~ep_old"])

        let newest = try XCTUnwrap(episodes.first)
        XCTAssertTrue(newest.isEpisode)
        XCTAssertTrue(newest.hasAudio)
        XCTAssertEqual(newest.media?.metadata?.title, "Second")
        XCTAssertEqual(newest.media?.metadata?.authorName, "The Show")
        XCTAssertEqual(newest.timeline.partDurations, [2400])
        XCTAssertEqual(newest.chapters.map(\.title), ["Intro", "Talk"])
        XCTAssertEqual(newest.media?.tracks?.first?.fileID, "71")

        // Made from its file when the server sent no track.
        let oldest = try XCTUnwrap(episodes.last)
        XCTAssertEqual(oldest.media?.tracks?.first?.fileID, "70")
        XCTAssertEqual(oldest.media?.tracks?.first?.fileExtension, "mp3")
        XCTAssertEqual(oldest.media?.duration ?? 0, 1800.5, accuracy: 0.01)
        XCTAssertTrue(oldest.chapters.isEmpty)
    }

    func testPodcastInProgressNamesItsEpisode() throws {
        let json = """
        { "libraryItems": [
            { "id": "li_1", "mediaType": "book", "media": { "numTracks": 2, "metadata": { "title": "A Book" } } },
            { "id": "li_2", "mediaType": "podcast", "progressLastUpdate": 5,
              "media": { "metadata": { "title": "The Show" }, "numEpisodes": 2 },
              "recentEpisode": { "id": "ep_new", "title": "Second", "audioFile": { "index": 1, "ino": "71", "duration": 2400 } } }
        ] }
        """
        let page = try JSONDecoder().decode(AudiobookshelfInProgress.self, from: Data(json.utf8))
        let podcast = try XCTUnwrap(page.libraryItems.last)
        let episode = try XCTUnwrap(podcast.recentEpisode)
        let item = AudiobookshelfAPI.episodeItem(episode, podcastID: podcast.id, podcastTitle: podcast.podcastTitle, libraryID: nil, progress: nil)
        XCTAssertEqual(item.id, "li_2~ep_new")
        XCTAssertTrue(item.hasAudio)
        XCTAssertFalse(page.libraryItems[0].isEpisode)
        XCTAssertTrue(page.libraryItems[0].hasAudio)
    }
}
