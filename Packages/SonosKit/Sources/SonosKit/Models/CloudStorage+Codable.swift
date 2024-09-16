import CloudStorage
import Foundation

private let sync = CloudStorageSync.shared

extension CloudStorage where Value: Codable {
    public init(wrappedValue: Value, _ key: String) {
        func syncGet() -> Value {
            guard let data = sync.data(for: key) else { return wrappedValue }
            do {
                let decoder = JSONDecoder()
                let value = try decoder.decode(Value.self, from: data)
                return value
            } catch {
                assertionFailure("\(error)")
                return wrappedValue
            }
        }
        func syncSet(_ newValue: Value) {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(newValue)
                sync.set(data, for: key)
            } catch {
                assertionFailure("\(error)")
            }
        }
        self.init(keyName: key, syncGet: syncGet, syncSet: syncSet)
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
            assertionFailure("\(error)")
            return nil
        }
    }
}
