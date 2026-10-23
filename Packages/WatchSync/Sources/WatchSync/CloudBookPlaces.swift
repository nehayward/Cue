import CryptoKit
import Foundation

/// What `CloudBookPlaces` keeps its places in: iCloud's key-value store, or
/// a dictionary in the tests.
public protocol BookPlaceStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    func removeObject(forKey key: String)
    var dictionaryRepresentation: [String: Any] { get }
}

extension NSUbiquitousKeyValueStore: BookPlaceStore {}

/// The books' places in iCloud's key-value store, so a place crosses
/// between the iPhone and the watch even when the two can't reach each
/// other: each reaches iCloud over its own Wi‑Fi or cellular, and both apps
/// name the same store (`com.apple.developer.ubiquity-kvstore-identifier`).
/// The watch connection (`WatchSyncMessage`) stays the quick way while
/// they're together; this is the way round when they aren't.
///
/// One key a book, so places in different books never collide: a hash of
/// the book's pick key, since a key can't be longer than 64 bytes and an
/// Audiobookshelf book's is nearly that alone, with the pick key kept in
/// the value. iCloud settles two writes to one key by whichever reached it
/// last, which needn't be the place that moved last, so no device takes the
/// store's word for it: each merges what it reads into its own places by
/// `WatchBookPlace.supersedes` (the place that moved last, a tie to the one
/// further in) and writes back only the places that beat the store's. A
/// device that hears the store come down with an older place than its own
/// writes its own back, so every device settles on the same place for each
/// book.
public struct CloudBookPlaces {
    /// Every key this keeps begins with it; the store holds settings too.
    static let keyPrefix = "bookPlace."
    /// The books kept at most, the places that moved longest ago going
    /// first: the store holds 1,024 keys, shared with the settings.
    static let bookLimit = 200

    private struct Entry: Codable {
        var book: String
        var place: WatchBookPlace
    }

    private let store: any BookPlaceStore

    public init(store: any BookPlaceStore = NSUbiquitousKeyValueStore.default) {
        self.store = store
    }

    /// Every book's place in the store.
    public func read() -> WatchBookPlaces {
        var places = WatchBookPlaces.empty
        for (_, entry) in entries() {
            places.record(entry.place, for: entry.book)
        }
        return places
    }

    /// Puts up each of `places` the store doesn't hold, or holds older, and
    /// lets the books that moved longest ago go past `bookLimit`. The books
    /// written, for the log.
    @discardableResult
    public func write(_ places: WatchBookPlaces) -> [String] {
        var written: [String] = []
        for (book, place) in places.places {
            let key = Self.key(for: book)
            if let held = entry(at: key), held.book == book, !place.supersedes(held.place) { continue }
            guard let data = try? JSONEncoder().encode(Entry(book: book, place: place)) else { continue }
            store.set(data, forKey: key)
            written.append(book)
        }
        if !written.isEmpty {
            trim()
        }
        return written.sorted()
    }

    /// The store's key for a book: the prefix and the first 12 bytes of
    /// its pick key's SHA-256, 34 bytes in all.
    static func key(for book: String) -> String {
        let digest = SHA256.hash(data: Data(book.utf8))
        return keyPrefix + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Each entry in the store by its key; one unreadable, or under a key
    /// that isn't its book's, is passed over.
    private func entries() -> [(key: String, entry: Entry)] {
        store.dictionaryRepresentation.keys.compactMap { key in
            guard key.hasPrefix(Self.keyPrefix), let entry = entry(at: key), Self.key(for: entry.book) == key else { return nil }
            return (key, entry)
        }
    }

    private func entry(at key: String) -> Entry? {
        store.data(forKey: key).flatMap { try? JSONDecoder().decode(Entry.self, from: $0) }
    }

    /// Past `bookLimit`, the books that moved longest ago go. Every device
    /// trims by the same rule, so they let the same books go.
    private func trim() {
        let all = entries()
        guard all.count > Self.bookLimit else { return }
        let oldestFirst = all.sorted { $1.entry.place.supersedes($0.entry.place) }
        for (key, _) in oldestFirst.prefix(all.count - Self.bookLimit) {
            store.removeObject(forKey: key)
        }
    }
}
