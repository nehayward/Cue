import CloudStorage
import Foundation
import OrderedCollections

private let sync = CloudStorageSync.shared

extension CloudStorage where Value: Codable {
    public init(wrappedValue: Value, _ key: String) {
        // CloudStorage calls `syncGet` on every read of the property, and
        // SwiftUI reads values like the play history in several bodies per
        // update. Decode only when the stored bytes change.
        let cache = DecodedValueCache<Value>()
        func syncGet() -> Value {
            guard let data = sync.data(for: key) else { return wrappedValue }
            return cache.value(for: data) { data in
                do {
                    return try JSONDecoder().decode(Value.self, from: data)
                } catch {
                    // A synced list can hold entries this build can't read,
                    // written by another device on a newer build (a new
                    // `ContentType` case, say). Keep everything that does
                    // decode: falling back to the default would show an empty
                    // list here, and the next write would replace the list on
                    // every device.
                    if let lossy = Value.self as? LossyDecodableCollection.Type,
                       let (value, dropped) = lossy.decodeLossily(from: data),
                       let value = value as? Value {
                        print("CloudStorage key \(key): skipped \(dropped) unreadable entries")
                        return value
                    }
                    // Corrupted/incompatible cloud data should fall back to the
                    // default rather than crash.
                    print("CloudStorage decode failed for key \(key): \(error)")
                    assertionFailure("\(error)")
                    return wrappedValue
                }
            }
        }
        func syncSet(_ newValue: Value) {
            do {
                let data = try JSONEncoder().encode(newValue)
                cache.store(newValue, for: data)
                sync.set(data, for: key)
            } catch {
                assertionFailure("\(error)")
            }
        }
        self.init(keyName: key, syncGet: syncGet, syncSet: syncSet)
    }
}

/// The last value decoded from a key's data. Comparing the bytes is a memcmp,
/// far cheaper than decoding them again.
private final class DecodedValueCache<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var value: Value?

    func value(for data: Data, decode: (Data) -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        if let value, data == self.data { return value }
        let decoded = decode(data)
        self.data = data
        value = decoded
        return decoded
    }

    func store(_ value: Value, for data: Data) {
        lock.lock()
        defer { lock.unlock() }
        self.data = data
        self.value = value
    }
}

/// A collection that can be decoded element by element, skipping the elements
/// that fail.
protocol LossyDecodableCollection {
    /// The collection of every element that decoded, and how many didn't; nil
    /// if `data` isn't a JSON array at all.
    static func decodeLossily(from data: Data) -> (value: Any, dropped: Int)?
}

/// Decodes as `nil` instead of throwing, so one bad element doesn't fail the
/// whole array.
private struct LossyElement<Element: Decodable>: Decodable {
    let value: Element?

    init(from decoder: Decoder) throws {
        value = try? Element(from: decoder)
    }
}

private func decodeElements<Element: Decodable>(_: Element.Type, from data: Data) -> (elements: [Element], dropped: Int)? {
    guard let wrapped = try? JSONDecoder().decode([LossyElement<Element>].self, from: data) else { return nil }
    let elements = wrapped.compactMap(\.value)
    return (elements, wrapped.count - elements.count)
}

extension Array: LossyDecodableCollection where Element: Codable {
    static func decodeLossily(from data: Data) -> (value: Any, dropped: Int)? {
        decodeElements(Element.self, from: data).map { ($0.elements, $0.dropped) }
    }
}

extension OrderedSet: LossyDecodableCollection where Element: Codable {
    // Also recovers a stored set that now contains duplicates, which the
    // whole-value decode rejects as dataCorrupted.
    static func decodeLossily(from data: Data) -> (value: Any, dropped: Int)? {
        decodeElements(Element.self, from: data).map { (OrderedSet($0.elements), $0.dropped) }
    }
}

extension CloudStorageSync {
    public func set<Value: Codable>(_ object: Value, forKey key: String) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(object)
            sync.set(data, for: key)
        } catch {
            assertionFailure("\(error)")
        }
    }

    public func codable<Value: Codable>(forKey key: String) -> Value? {
        guard let data = sync.data(for: key) else { return nil }
        do {
            let decoder = JSONDecoder()
            let value = try decoder.decode(Value.self, from: data)
            return value
        } catch {
            if let lossy = Value.self as? LossyDecodableCollection.Type,
               let (value, dropped) = lossy.decodeLossily(from: data),
               let value = value as? Value {
                print("CloudStorage key \(key): skipped \(dropped) unreadable entries")
                return value
            }
            print("CloudStorage decode failed for key \(key): \(error)")
            return nil
        }
    }
}
