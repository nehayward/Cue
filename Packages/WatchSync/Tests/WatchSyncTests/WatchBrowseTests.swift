import XCTest
@testable import WatchSync

final class WatchBrowseTests: XCTestCase {
    private let artist = WatchContentRef(source: .subsonic, kind: .artist, id: "ar-1", title: "Artist", subtitle: "", artworkURL: nil)

    func testPathsRoundTripAsNavigationValues() throws {
        let paths: [WatchBrowsePath] = [
            .root,
            .source(.plex),
            .section(.subsonic, .recentlyAdded),
            .artist(artist),
        ]
        for path in paths {
            XCTAssertEqual(try JSONDecoder().decode(WatchBrowsePath.self, from: JSONEncoder().encode(path)), path)
        }
        XCTAssertEqual(Set(paths).count, paths.count)
    }

    func testAFullPageOfLongRowsStaysSmall() throws {
        let items = (0 ..< WatchBrowsePage.pageSize).map { index in
            let ref = WatchContentRef(
                source: .plex,
                kind: .album,
                id: "2b5d1c0f9a8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c%3A3%3A\(100_000 + index)",
                title: "A Fairly Long Album Title Number \(index) (Deluxe Edition)",
                subtitle: "Some Artist With A Long Name",
                artworkURL: URL(string: "https://192-168-1-20.0123456789abcdef0123456789abcdef.plex.direct:32400/photo/:/transcode?width=300&height=300&url=%2Flibrary%2Fmetadata%2F\(index)%2Fthumb&X-Plex-Token=abcdefghijklmnopqrst")
            )
            return WatchBrowseItem(id: ref.id, title: ref.title, subtitle: ref.subtitle, artworkURL: ref.artworkURL, content: ref, collectionKey: "album-\(ref.id)")
        }
        let page = WatchBrowsePage(title: "Albums", items: items, nextOffset: 40)
        XCTAssertLessThan(try JSONEncoder().encode(page).count, 60_000)
    }

    func testQualitiesSayWhatTheyCost() {
        XCTAssertEqual(WatchDownloadQuality.high.megabytesPerSong, 8)
        XCTAssertEqual(WatchDownloadQuality.medium.megabytesPerSong, 6)
        XCTAssertEqual(WatchDownloadQuality.small.megabytesPerSong, 4)
        XCTAssertNil(WatchDownloadQuality.original.bitrate)
        XCTAssertEqual(WatchDownloadQuality.small.detail, "MP3 128 kbps • about 4 MB a song")
    }
}

final class WatchKeysTests: XCTestCase {
    // The same answers as DownloadNamingTests in SonosKit: the two have to
    // agree, or a song added from both devices comes down twice.
    func testTrackKeysMatchTheDownloadManager() {
        XCTAssertEqual(WatchKeys.track(source: .plex, id: "12345"), "12345")
        XCTAssertEqual(WatchKeys.track(source: .subsonic, id: "tr/ab:c.d"), "subsonic-tr-ab-c-d")
        XCTAssertEqual(WatchKeys.track(source: .plex, id: "abc%3A3%3A99"), "abc%3A3%3A99")
    }

    func testCollectionKeysPutTheKindFirst() {
        XCTAssertEqual(WatchKeys.collection(kind: .album, source: .subsonic, id: "al-1"), "album-subsonic-al-1")
        XCTAssertEqual(WatchKeys.collection(kind: .playlist, source: .plex, id: "m%3A3%3A7"), "playlist-m%3A3%3A7")
        XCTAssertEqual(WatchKeys.collection(kind: .artist, source: .subsonic, id: "ar.1"), "artist-subsonic-ar-1")
    }
}
