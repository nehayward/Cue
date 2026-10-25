import Foundation

/// A shelf's last read from its server, kept in Caches: the Audiobooks tab
/// draws it at once and reads the server behind it, rather than showing
/// placeholders until a slow server (Plex over cellular) answers or doesn't.
enum ShelfCache {
    private static var directory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Shelves", isDirectory: true)
    }

    static func load<Value: Decodable>(_ type: Value.Type, named name: String) -> Value? {
        guard let url = directory?.appendingPathComponent("\(name).json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Written off the main thread; nil removes it.
    static func save<Value: Encodable & Sendable>(_ value: Value?, named name: String) {
        guard let directory else { return }
        let url = directory.appendingPathComponent("\(name).json")
        Task.detached(priority: .utility) {
            guard let value, let data = try? JSONEncoder().encode(value) else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
