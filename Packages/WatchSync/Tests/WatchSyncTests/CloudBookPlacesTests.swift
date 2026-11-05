import XCTest
@testable import WatchSync

/// iCloud's key-value store in memory. `serverTakes` stands for iCloud
/// settling two devices' writes to one key by whichever reached it last.
private final class MemoryStore: BookPlaceStore {
    var values: [String: Any] = [:]

    func data(forKey key: String) -> Data? { values[key] as? Data }
    func set(_ data: Data?, forKey key: String) { values[key] = data }
    func removeObject(forKey key: String) { values[key] = nil }
    var dictionaryRepresentation: [String: Any] { values }

    func serverTakes(_ other: MemoryStore, key: String) {
        values[key] = other.values[key]
    }
}

final class CloudBookPlacesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    /// An Audiobookshelf book's pick key, 61 bytes alone.
    private let longBook = "audiobook-audiobookshelf-0b8f7c2e-3d1a-4f5b-9c6e-2a7d8e9f0a1b"

    private func place(_ position: TimeInterval, at seconds: TimeInterval) -> WatchBookPlace {
        WatchBookPlace(position: position, duration: 36_000, isFinished: false, updatedAt: t0.addingTimeInterval(seconds))
    }

    private func places(_ entries: [String: WatchBookPlace]) -> WatchBookPlaces {
        WatchBookPlaces(places: entries)
    }

    func testPlacesComeBackAsWritten() {
        let cloud = CloudBookPlaces(store: MemoryStore())
        let written = places(["audiobook-1234": place(100, at: 1), longBook: place(900, at: 2)])
        XCTAssertEqual(cloud.write(written), ["audiobook-1234", longBook].sorted())
        XCTAssertEqual(cloud.read(), written)
    }

    func testKeysFitTheStoresLimit() {
        let key = CloudBookPlaces.key(for: longBook)
        XCTAssertLessThanOrEqual(key.utf8.count, 64)
        XCTAssertEqual(key, CloudBookPlaces.key(for: longBook))
        XCTAssertNotEqual(key, CloudBookPlaces.key(for: "audiobook-1234"))
    }

    func testANewerPlaceInTheStoreIsNotOverwritten() {
        let store = MemoryStore()
        let cloud = CloudBookPlaces(store: store)
        cloud.write(places(["a": place(900, at: 5)]))
        XCTAssertEqual(cloud.write(places(["a": place(100, at: 4)])), [])
        XCTAssertEqual(cloud.read()["a"]?.position, 900)
        XCTAssertEqual(cloud.write(places(["a": place(900, at: 5)])), [], "the same place isn't written again")
    }

    func testAnOlderPlaceInTheStoreIsReplaced() {
        let cloud = CloudBookPlaces(store: MemoryStore())
        cloud.write(places(["a": place(900, at: 5)]))
        XCTAssertEqual(cloud.write(places(["a": place(100, at: 6)])), ["a"])
        XCTAssertEqual(cloud.read()["a"]?.position, 100, "moving back is a move too: the later one wins")
    }

    /// The watch and the iPhone, apart, each listen to the same book; the
    /// watch listened last, but the iPhone's older place reaches iCloud
    /// last and wins there. Both settle on the watch's.
    func testDevicesSettleOnThePlaceThatMovedLast() {
        let watchStore = MemoryStore()
        let phoneStore = MemoryStore()
        let watchCloud = CloudBookPlaces(store: watchStore)
        let phoneCloud = CloudBookPlaces(store: phoneStore)
        var watch = places(["a": place(2_000, at: 20)])
        var phone = places(["a": place(1_500, at: 10)])
        watchCloud.write(watch)
        phoneCloud.write(phone)

        // iCloud keeps the iPhone's, and both stores come down with it.
        let key = CloudBookPlaces.key(for: "a")
        watchStore.serverTakes(phoneStore, key: key)

        // The watch hears of the change: it keeps its own and writes it back.
        watch = watch.merged(with: watchCloud.read())
        XCTAssertEqual(watch["a"]?.position, 2_000)
        XCTAssertEqual(watchCloud.write(watch), ["a"])

        // That reaches iCloud and the iPhone, which takes it.
        phoneStore.serverTakes(watchStore, key: key)
        phone = phone.merged(with: phoneCloud.read())
        XCTAssertEqual(phone["a"]?.position, 2_000)
        XCTAssertEqual(phoneCloud.write(phone), [], "nothing more to send: settled")
    }

    func testOtherKeysAndDamagedEntriesArePassedOver() {
        let store = MemoryStore()
        store.values["playerTheme"] = "dark"
        store.values[CloudBookPlaces.keyPrefix + "junk"] = Data("not json".utf8)
        let cloud = CloudBookPlaces(store: store)
        cloud.write(places(["a": place(100, at: 1)]))
        // An entry moved under another book's key isn't that book's.
        store.values[CloudBookPlaces.key(for: "b")] = store.values[CloudBookPlaces.key(for: "a")]

        XCTAssertEqual(cloud.read(), places(["a": place(100, at: 1)]))
        XCTAssertEqual(store.values["playerTheme"] as? String, "dark")
    }

    /// The watch's books go under the watch's own pick keys, so the watch
    /// and the other devices name a book alike; Files books, which the
    /// watch doesn't hold, under their service and id.
    func testBookKeysAreTheWatchsPickKeys() {
        let plex = WatchPick(source: .plex, kind: .audiobook, id: "/library/metadata/1234", title: "A Book")
        XCTAssertEqual(CloudBookPlaces.bookKey(service: "plex", id: "/library/metadata/1234"), plex.key)
        let shelf = WatchPick(source: .audiobookshelf, kind: .audiobook, id: "0b8f7c2e-3d1a-4f5b-9c6e-2a7d8e9f0a1b", title: "A Book")
        XCTAssertEqual(CloudBookPlaces.bookKey(service: "audiobookshelf", id: shelf.id), shelf.key)
        XCTAssertEqual(CloudBookPlaces.bookKey(service: "files", id: "9f86d081884c7d65"), "audiobook-files-9f86d081884c7d65")
    }

    func testPlacesCarryTheirBookAndDevice() {
        let cloud = CloudBookPlaces(store: MemoryStore())
        let book = CloudBookPlaces.CloudBook(service: "files", id: "9f86d081884c7d65")
        let key = CloudBookPlaces.bookKey(service: book.service, id: book.id)
        cloud.write(places([key: place(100, at: 1)]), books: [key: book], device: .mac)
        cloud.write(places(["audiobook-1234": place(200, at: 2)]))

        let all = Dictionary(uniqueKeysWithValues: cloud.readAll().map { ($0.book, $0) })
        XCTAssertEqual(all[key]?.identity, book)
        XCTAssertEqual(all[key]?.device, .mac)
        XCTAssertEqual(all[key]?.place, place(100, at: 1))
        XCTAssertNil(all["audiobook-1234"]?.identity, "a place written without its book")
        XCTAssertNil(all["audiobook-1234"]?.device)
    }

    /// A device of a kind this build doesn't know yet reads as none, and
    /// its place is still read.
    func testAnUnknownDeviceStillReads() throws {
        let store = MemoryStore()
        let placeJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(place(100, at: 1)))
        let entry: [String: Any] = ["book": "a", "place": placeJSON, "device": "toaster"]
        store.values[CloudBookPlaces.key(for: "a")] = try JSONSerialization.data(withJSONObject: entry)
        let cloud = CloudBookPlaces(store: store)

        XCTAssertEqual(cloud.readAll().first?.place, place(100, at: 1))
        XCTAssertNil(cloud.readAll().first?.device)
        XCTAssertEqual(cloud.read()["a"]?.position, 100)
    }

    /// A place older than every book a full store keeps would be trimmed as
    /// soon as it was written, and written again next time: it isn't.
    func testAPlaceTooOldForAFullStoreIsNotWritten() {
        let store = MemoryStore()
        let cloud = CloudBookPlaces(store: store)
        var full = WatchBookPlaces.empty
        for index in 0 ..< CloudBookPlaces.bookLimit {
            full.record(place(Double(index), at: 100 + Double(index)), for: "book-\(index)")
        }
        cloud.write(full)

        XCTAssertEqual(cloud.write(places(["old": place(5, at: 1)])), [])
        XCTAssertNil(cloud.read()["old"])
        XCTAssertNotNil(cloud.read()["book-0"])

        XCTAssertEqual(cloud.write(places(["new": place(5, at: 1_000)])), ["new"])
        let kept = cloud.read()
        XCTAssertEqual(kept.places.count, CloudBookPlaces.bookLimit)
        XCTAssertNotNil(kept["new"])
        XCTAssertNil(kept["book-0"], "the book that moved longest ago makes room")
    }

    func testTheBooksThatMovedLongestAgoGoPastTheLimit() {
        let store = MemoryStore()
        let cloud = CloudBookPlaces(store: store)
        var many = WatchBookPlaces.empty
        for index in 0 ..< CloudBookPlaces.bookLimit + 5 {
            many.record(place(Double(index), at: Double(index)), for: "book-\(index)")
        }
        cloud.write(many)

        let kept = cloud.read()
        XCTAssertEqual(kept.places.count, CloudBookPlaces.bookLimit)
        XCTAssertNil(kept["book-0"])
        XCTAssertNil(kept["book-4"])
        XCTAssertNotNil(kept["book-5"])
        XCTAssertNotNil(kept["book-\(CloudBookPlaces.bookLimit + 4)"])
    }
}
