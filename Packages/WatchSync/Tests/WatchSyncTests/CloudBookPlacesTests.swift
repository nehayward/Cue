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
