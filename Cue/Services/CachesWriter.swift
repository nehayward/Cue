import Foundation

/// Writes what Cue keeps in Caches as JSON, off the main thread and one
/// write after another, so a later write never lands before an earlier one
/// and the main thread neither encodes nor waits on the disk. Reads are
/// synchronous, for a store loading as it starts.
actor CachesWriter {
    static let shared = CachesWriter()

    /// Writes `value` to Caches/`name`, making its folder if need be.
    func write(_ value: some Encodable & Sendable, to name: String) {
        guard let url = Self.url(name), let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// What Caches/`name` holds, or nil when it's missing or unreadable.
    nonisolated static func read<Value: Decodable>(_ type: Value.Type, from name: String) -> Value? {
        guard let url = url(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private nonisolated static func url(_ name: String) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: name)
    }
}
