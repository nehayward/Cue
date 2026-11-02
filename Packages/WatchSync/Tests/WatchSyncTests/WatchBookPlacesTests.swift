import XCTest
@testable import WatchSync

final class WatchBookPlacesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func place(_ position: TimeInterval, at seconds: TimeInterval, finished: Bool = false) -> WatchBookPlace {
        WatchBookPlace(position: position, duration: 3_600, isFinished: finished, updatedAt: t0.addingTimeInterval(seconds))
    }

    func testTheLaterPlaceWins() {
        var watch = WatchBookPlaces.empty
        var phone = WatchBookPlaces.empty
        watch.record(place(100, at: 1), for: "a")
        phone.record(place(900, at: 2), for: "a")
        phone.record(place(50, at: 1), for: "b")

        let merged = watch.merged(with: phone)
        XCTAssertEqual(merged["a"]?.position, 900)
        XCTAssertEqual(merged["b"]?.position, 50)
        XCTAssertEqual(phone.merged(with: watch), merged)
    }

    func testAnOlderPlaceIsNotKept() {
        var places = WatchBookPlaces.empty
        XCTAssertTrue(places.record(place(900, at: 5), for: "a"))
        XCTAssertFalse(places.record(place(100, at: 4), for: "a"))
        XCTAssertFalse(places.record(place(900, at: 5), for: "a"))
        XCTAssertEqual(places["a"]?.position, 900)
    }

    /// One moment told both ways, rounded apart, settles the same on both
    /// sides, so neither keeps sending it back.
    func testATieSettlesTheSameBothWays() {
        let watch = WatchBookPlaces(places: ["a": place(100, at: 1)])
        let phone = WatchBookPlaces(places: ["a": place(101, at: 1)])
        XCTAssertEqual(watch.merged(with: phone), phone.merged(with: watch))
        XCTAssertEqual(watch.merged(with: phone)["a"]?.position, 101)
    }

    func testNewsIsWhatTheOtherSideLacksOrWouldTake() {
        let phone = WatchBookPlaces(places: ["a": place(900, at: 2)])
        var watch = WatchBookPlaces(places: ["a": place(100, at: 1)])
        XCTAssertTrue(phone.hasNews(for: watch))
        XCTAssertFalse(watch.hasNews(for: phone))

        watch = watch.merged(with: phone)
        XCTAssertFalse(watch.hasNews(for: phone))
        XCTAssertFalse(phone.hasNews(for: watch))

        watch.record(place(10, at: 3), for: "b")
        XCTAssertTrue(watch.hasNews(for: phone))
        XCTAssertFalse(watch.restricted(to: ["a"]).hasNews(for: phone))
    }

    func testPlacesTravelWithThePicks() throws {
        var places = WatchBookPlaces.empty
        places.record(place(1_234.5, at: 7, finished: true), for: "audiobook-audiobookshelf-li_1")
        let context = try WatchSyncMessage.context(picks: .empty, places: places)
        XCTAssertEqual(WatchSyncMessage.places(in: context), places)
        XCTAssertNil(WatchSyncMessage.places(in: try WatchSyncMessage.context(picks: .empty)))
    }
}

final class WatchBookPicksTests: XCTestCase {
    func testABookIsAPickOfItsOwn() {
        XCTAssertEqual(WatchKeys.pick(kind: .audiobook, source: .audiobookshelf, id: "li_7"), "audiobook-audiobookshelf-li_7")
        XCTAssertEqual(WatchKeys.pick(kind: .audiobook, source: .plex, id: "m%3A3%3A7"), "audiobook-m%3A3%3A7")
        // An Audiobookshelf file's id keeps its bars, as the iPhone's
        // download manager names it.
        XCTAssertEqual(WatchKeys.song(source: .audiobookshelf, id: "li_7|2|8812"), "audiobookshelf-li_7|2|8812")
    }

    /// A newer Cue on the other device may send a kind this one doesn't
    /// know: it's left out, and the rest still arrive.
    func testAnUnknownPickDoesNotLoseTheRest() throws {
        let json = """
        {"items":[
          {"source":"plex","kind":"album","id":"1","title":"Kept","subtitle":"","addedAt":10},
          {"source":"plex","kind":"podcast","id":"2","title":"Unknown","subtitle":"","addedAt":20},
          {"source":"tidal","kind":"album","id":"3","title":"Unknown","subtitle":"","addedAt":30}
        ],"removed":{"album-9":5}}
        """
        let picks = try WatchPicks.decoded(from: Data(json.utf8))
        XCTAssertEqual(picks.items.map(\.title), ["Kept"])
        XCTAssertEqual(picks.removed.keys.sorted(), ["album-9"])
    }

    func testTheiPhoneLendsItsAudiobookshelfToken() throws {
        let credentials = WatchCredentials(
            plex: .init(token: "tok", serverID: "srv", librarySectionID: "3", connectionPreference: "auto", hasBooks: true, bookLibraryKeys: ["7"], includesGenreTaggedBooks: false),
            audiobookshelf: .init(serverAddress: "https://books.example", username: "me", accessToken: "jwt")
        )
        let context = try WatchSyncMessage.context(picks: .empty, credentials: credentials)
        XCTAssertEqual(WatchSyncMessage.credentials(in: context), credentials)
        XCTAssertEqual(WatchSyncMessage.credentials(in: try WatchSyncMessage.credentialsReply(credentials)), credentials)
    }

    /// Sign-ins an older iPhone sent, without the book fields, still read.
    func testSignInsFromBeforeBooksStillRead() throws {
        let json = #"{"plex":{"token":"tok","serverID":"srv"}}"#
        let credentials = try JSONDecoder().decode(WatchCredentials.self, from: Data(json.utf8))
        XCTAssertEqual(credentials.plex?.token, "tok")
        XCTAssertNil(credentials.plex?.hasBooks)
        XCTAssertNil(credentials.audiobookshelf)
    }

    func testTheRequestForSignInsIsKnown() {
        XCTAssertTrue(WatchSyncMessage.isCredentialsRequest(WatchSyncMessage.credentialsRequest))
        XCTAssertFalse(WatchSyncMessage.isCredentialsRequest([:]))
    }
}
