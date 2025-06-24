import Foundation

final class MemoryFileCache {
    static let shared = MemoryFileCache()

    private let memoryCache = NSCache<NSString, CacheBox>()
    private let directory: URL
    private let queue = DispatchQueue(label: "MemoryFileCacheQueue")

    init(subdirectory: String? = nil) {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        if let subdirectory = subdirectory {
            self.directory = base.appendingPathComponent(subdirectory, isDirectory: true)
            try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        } else {
            self.directory = base
        }
    }

    func save<T: Codable>(_ value: T, forKey key: String) {
        memoryCache.setObject(CacheBox(value), forKey: key as NSString)

        queue.async {
            let url = self.fileURL(for: key)
            do {
                let data = try JSONEncoder().encode(value)
                try data.write(to: url, options: [.atomic])
            } catch {
                print("❌ Failed to save to disk for key '\(key)': \(error)")
            }
        }
    }

    func load<T: Codable>(forKey key: String, as type: T.Type) -> T? {
        if let box = memoryCache.object(forKey: key as NSString),
           let value = box.value as? T {
            return value
        }

        let url = fileURL(for: key)
        var result: T?

        queue.sync {
            if let data = try? Data(contentsOf: url),
               let value = try? JSONDecoder().decode(T.self, from: data) {
                result = value
                memoryCache.setObject(CacheBox(value), forKey: key as NSString)
            }
        }

        return result
    }

    func delete(forKey key: String) {
        memoryCache.removeObject(forKey: key as NSString)

        queue.async {
            try? FileManager.default.removeItem(at: self.fileURL(for: key))
        }
    }

    func clear() {
        memoryCache.removeAllObjects()

        queue.async {
            guard let files = try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil) else { return }
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(key + ".json")
    }

    private class CacheBox {
        let value: Any
        init(_ value: Any) {
            self.value = value
        }
    }
}
