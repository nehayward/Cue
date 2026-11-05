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
/// between the listener's devices — the iPhone, the iPad, the Mac and the
/// watch — even when they can't reach each other: each reaches iCloud over
/// its own Wi‑Fi or cellular, and every app names the same store
/// (`com.apple.developer.ubiquity-kvstore-identifier`). The watch
/// connection (`WatchSyncMessage`) stays the quick way while the iPhone and
/// the watch are together; this is the way round when they aren't, and the
/// only way between the iPhone and the Mac.
///
/// One key a book, so places in different books never collide: a hash of
/// the book's key (`bookKey(service:id:)`, a pick's key for the books the
/// watch can hold), since a key can't be longer than 64 bytes and an
/// Audiobookshelf book's is nearly that alone, with the book's key kept in
/// the value. iCloud settles two writes to one key by whichever reached it
/// last, which needn't be the place that moved last, so no device takes the
/// store's word for it: each merges what it reads into its own places by
/// `WatchBookPlace.supersedes` (the place that moved last, a tie to the one
/// further in) and writes back only the places that beat the store's. A
/// device that hears the store come down with an older place than its own
/// writes its own back, so every device settles on the same place for each
/// book.
///
/// Each place carries which book it is (`CloudBook`), for a device that has
/// never seen the book (a book only ever played on the Mac, read on the
/// iPhone), and the kind of device that wrote it (`Device`), for the book's
/// history. Both are optional: places written before they were noted have
/// neither.
public struct CloudBookPlaces {
    /// Every key this keeps begins with it; the store holds settings too.
    static let keyPrefix = "bookPlace."
    /// The books kept at most, the places that moved longest ago going
    /// first: the store holds 1,024 keys, shared with the settings.
    static let bookLimit = 200

    /// Which book a place is in: its service, as the apps name it (`plex`,
    /// `audiobookshelf`, `files`; a `WatchSource`'s raw value for the
    /// sources the watch knows), and its id there.
    public struct CloudBook: Hashable, Sendable {
        public var service: String
        public var id: String

        public init(service: String, id: String) {
            self.service = service
            self.id = id
        }
    }

    /// The kind of device a place was written on.
    public enum Device: String, Sendable {
        case iPhone, iPad, mac, watch, vision
    }

    /// A place as the store has it, with what it says of where it's from.
    public struct Place: Equatable, Sendable {
        /// The book's key (`bookKey(service:id:)`).
        public var book: String
        public var place: WatchBookPlace
        /// Nil for a place written before books were named.
        public var identity: CloudBook?
        /// Nil for a place written before devices were named, or on a
        /// kind of device this build doesn't know.
        public var device: Device?
    }

    private struct Entry: Codable {
        var book: String
        var place: WatchBookPlace
        // Optional, and decoded as such by every build: one that doesn't
        // know them passes over them.
        var service: String?
        var id: String?
        var device: String?

        var identity: CloudBook? {
            guard let service, let id else { return nil }
            return CloudBook(service: service, id: id)
        }
    }

    private let store: any BookPlaceStore

    public init(store: any BookPlaceStore = NSUbiquitousKeyValueStore.default) {
        self.store = store
    }

    /// The key a book's place goes under: the watch's pick key for a book
    /// from a source the watch knows (Plex, Audiobookshelf), so the watch
    /// and the other devices name it alike; the service and id otherwise
    /// (Files).
    public static func bookKey(service: String, id: String) -> String {
        if let source = WatchSource(rawValue: service) {
            return WatchKeys.pick(kind: .audiobook, source: source, id: id)
        }
        return "\(WatchPick.Kind.audiobook.rawValue)-\(service)-\(id)"
    }

    /// Every book's place in the store.
    public func read() -> WatchBookPlaces {
        var places = WatchBookPlaces.empty
        for (_, entry) in entries() {
            places.record(entry.place, for: entry.book)
        }
        return places
    }

    /// Every book's place in the store, with which book it is and the
    /// device that wrote it, where the place says.
    public func readAll() -> [Place] {
        entries().map { held in
            Place(book: held.entry.book, place: held.entry.place, identity: held.entry.identity, device: held.entry.device.flatMap(Device.init(rawValue:)))
        }
    }

    /// Puts up each of `places` the store doesn't hold, or holds older,
    /// named by `books` (by book key) where it has them and as written on
    /// `device`, and lets the books that moved longest ago go past
    /// `bookLimit`. A place that would go straight back out — older than
    /// every book a full store keeps — isn't put up: it would be on every
    /// write. The books written, for the log.
    @discardableResult
    public func write(_ places: WatchBookPlaces, books: [String: CloudBook] = [:], device: Device? = nil) -> [String] {
        let held = entries()
        var heldByKey: [String: Entry] = [:]
        for (key, entry) in held {
            heldByKey[key] = entry
        }
        var news: [(key: String, entry: Entry)] = []
        for (book, place) in places.places {
            let key = Self.key(for: book)
            if let entry = heldByKey[key], entry.book == book, !place.supersedes(entry.place) { continue }
            let identity = books[book]
            news.append((key, Entry(book: book, place: place, service: identity?.service, id: identity?.id, device: device?.rawValue)))
        }
        guard !news.isEmpty else { return [] }
        // The newest `bookLimit` of the store's and the new together: the
        // new ones among them are written.
        let newKeys = Set(news.map { $0.key })
        var candidates: [(key: String, place: WatchBookPlace, isNew: Bool)] = []
        for (key, entry) in held where !newKeys.contains(key) {
            candidates.append((key, entry.place, false))
        }
        for (key, entry) in news {
            candidates.append((key, entry.place, true))
        }
        candidates.sort { $0.place.supersedes($1.place) }
        let kept = Set(candidates.prefix(Self.bookLimit).filter { $0.isNew }.map { $0.key })
        var written: [String] = []
        for (key, entry) in news where kept.contains(key) {
            guard let data = try? JSONEncoder().encode(entry) else { continue }
            store.set(data, forKey: key)
            written.append(entry.book)
        }
        if !written.isEmpty {
            trim()
        }
        return written.sorted()
    }

    /// The store's key for a book: the prefix and the first 12 bytes of
    /// its book key's SHA-256, 34 bytes in all.
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
