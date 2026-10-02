import XCTest
@testable import WatchSync

final class WatchPicksTests: XCTestCase {
    private func pick(_ kind: WatchPick.Kind, _ id: String, source: WatchSource = .subsonic) -> WatchPick {
        WatchPick(source: source, kind: kind, id: id, title: "\(kind) \(id)", addedAt: Date(timeIntervalSince1970: 1))
    }

    func testAddingPutsAPickFirstAndOnlyOnce() {
        var picks = WatchPicks.empty
        picks.add(pick(.album, "a"))
        picks.add(pick(.playlist, "p"))
        picks.add(pick(.album, "a"))
        XCTAssertEqual(picks.items.map(\.key), ["album-subsonic-a", "playlist-subsonic-p"])
        XCTAssertTrue(picks.contains(key: "playlist-subsonic-p"))

        picks.remove(key: "album-subsonic-a")
        XCTAssertEqual(picks.items.map(\.key), ["playlist-subsonic-p"])
        picks.removeAll()
        XCTAssertTrue(picks.items.isEmpty)
    }

    func testAnAlbumAndAPlaylistWithOneIdStayApart() {
        var picks = WatchPicks.empty
        picks.add(pick(.album, "7"))
        picks.add(pick(.playlist, "7"))
        XCTAssertEqual(picks.items.count, 2)
    }

    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    func testChangesMadeApartBothSurvive() {
        var watch = WatchPicks.empty
        var phone = WatchPicks.empty
        watch.add(pick(.album, "a"), at: at(1))
        phone.add(pick(.album, "b"), at: at(2))

        let merged = watch.merged(with: phone)
        XCTAssertEqual(merged.items.map(\.key), ["album-subsonic-b", "album-subsonic-a"])
        XCTAssertEqual(phone.merged(with: watch), merged)
    }

    func testTheLaterOfAddAndRemoveWins() {
        var watch = WatchPicks.empty
        watch.add(pick(.album, "a"), at: at(1))
        var phone = watch

        phone.remove(key: "album-subsonic-a", at: at(2))
        XCTAssertFalse(watch.merged(with: phone).contains(key: "album-subsonic-a"))
        XCTAssertEqual(watch.merged(with: phone).removed.keys.sorted(), ["album-subsonic-a"])

        watch.add(pick(.album, "a"), at: at(3))
        let merged = watch.merged(with: phone)
        XCTAssertTrue(merged.contains(key: "album-subsonic-a"))
        XCTAssertTrue(merged.removed.isEmpty)
    }

    func testMergingWhatYouAlreadyHaveChangesNothing() {
        var picks = WatchPicks.empty
        picks.add(pick(.album, "a"), at: at(1))
        picks.add(pick(.song, "s"), at: at(2))
        picks.remove(key: "album-subsonic-a", at: at(3))
        XCTAssertEqual(picks.merged(with: picks), picks)
        XCTAssertEqual(picks.merged(with: .empty), picks)
        XCTAssertEqual(WatchPicks.empty.merged(with: picks), picks)
    }

    func testOldTombstonesAreDropped() {
        var picks = WatchPicks.empty
        picks.add(pick(.album, "a"), at: at(0))
        picks.remove(key: "album-subsonic-a", at: at(1))
        picks.add(pick(.album, "b"), at: at(2))
        picks.remove(key: "album-subsonic-b", at: at(WatchPicks.tombstoneLifetime + 10))
        XCTAssertEqual(picks.removed.keys.sorted(), ["album-subsonic-b"])
    }
}

final class WatchKeysTests: XCTestCase {
    // The same answers as DownloadNamingTests in SonosKit: the two have to
    // agree, or a song added from both devices comes down twice.
    func testSongKeysMatchTheDownloadManager() {
        XCTAssertEqual(WatchKeys.song(source: .plex, id: "12345"), "12345")
        XCTAssertEqual(WatchKeys.song(source: .subsonic, id: "tr/ab:c.d"), "subsonic-tr-ab-c-d")
        XCTAssertEqual(WatchKeys.song(source: .plex, id: "abc%3A3%3A99"), "abc%3A3%3A99")
    }

    func testPickKeysPutTheKindFirst() {
        XCTAssertEqual(WatchKeys.pick(kind: .album, source: .subsonic, id: "al-1"), "album-subsonic-al-1")
        XCTAssertEqual(WatchKeys.pick(kind: .playlist, source: .plex, id: "m%3A3%3A7"), "playlist-m%3A3%3A7")
        XCTAssertEqual(WatchKeys.pick(kind: .song, source: .subsonic, id: "tr.1"), "song-subsonic-tr-1")
    }
}

final class WatchSyncMessageTests: XCTestCase {
    private func picks(count: Int) -> WatchPicks {
        var picks = WatchPicks.empty
        for index in 0 ..< count {
            picks.add(WatchPick(
                source: .plex,
                kind: .album,
                id: "2b5d1c0f9a8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c%3A3%3A\(10_000 + index)",
                title: "A Fairly Long Album Title \(index) (Deluxe Edition)",
                subtitle: "Some Artist • 2019",
                artworkURL: URL(string: "https://192-168-1-20.0123456789abcdef.plex.direct:32400/photo/:/transcode?width=300&height=300&url=%2Flibrary%2Fmetadata%2F\(index)%2Fthumb&X-Plex-Token=abcdefghijklmnopqrst"),
                addedAt: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }
        return picks
    }

    func testTheiPhonesContextCarriesPicksAndSignIns() throws {
        let picks = picks(count: 3)
        let credentials = WatchCredentials(
            plex: .init(token: "tok", serverID: "srv", librarySectionID: "3", connectionPreference: "auto"),
            subsonic: .init(serverAddress: "https://music.example", username: "me", password: "pw")
        )
        let context = try WatchSyncMessage.context(picks: picks, credentials: credentials)
        XCTAssertEqual(WatchSyncMessage.picks(in: context), picks)
        XCTAssertEqual(WatchSyncMessage.credentials(in: context), credentials)
    }

    func testTheWatchsContextCarriesPicksOnly() throws {
        let context = try WatchSyncMessage.context(picks: picks(count: 1))
        XCTAssertNotNil(WatchSyncMessage.picks(in: context))
        XCTAssertNil(WatchSyncMessage.credentials(in: context))
        XCTAssertNil(WatchSyncMessage.picks(in: [:]))
        XCTAssertNil(WatchSyncMessage.picks(in: [WatchSyncMessage.picksKey: Data([9, 9])]))
    }

    func testSendingAgainChangesTheContext() throws {
        let picks = picks(count: 1)
        let first = try WatchSyncMessage.context(picks: picks, sentAt: Date(timeIntervalSince1970: 1))
        let second = try WatchSyncMessage.context(picks: picks, sentAt: Date(timeIntervalSince1970: 2))
        XCTAssertNotEqual(first[WatchSyncMessage.sentAtKey] as? Double, second[WatchSyncMessage.sentAtKey] as? Double)
    }

    /// Picks are ids, so even a couple of hundred fit in a context, packed or
    /// not (Linux has no LZFSE, so this runs on the plain size).
    func testTwoHundredPicksFit() throws {
        let context = try WatchSyncMessage.context(picks: picks(count: 200))
        let packed = try XCTUnwrap(context[WatchSyncMessage.picksKey] as? Data)
        XCTAssertLessThan(packed.count, 120_000)
        XCTAssertEqual(WatchSyncMessage.picks(in: context)?.items.count, 200)
    }

    func testQualitiesSayWhatTheyCost() {
        XCTAssertEqual(WatchDownloadQuality.high.megabytesPerSong, 8)
        XCTAssertEqual(WatchDownloadQuality.small.detail, "MP3 128 kbps • about 4 MB a song")
        XCTAssertNil(WatchDownloadQuality.original.bitrate)
    }
}
