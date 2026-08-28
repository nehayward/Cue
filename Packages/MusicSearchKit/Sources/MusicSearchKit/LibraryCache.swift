import Foundation

/// A self-hosted library kept on disk, so syncing it is genuinely one-time
/// rather than once per launch.
///
/// It lives in Caches because it is derived data — the system may reclaim it,
/// and the only cost is syncing again. Two things decide whether a saved copy
/// is still usable: the `owner` string, which identifies the server and login
/// it came from, and whether the caller's own freshness check passes (both
/// Subsonic and Plex can ask the server for a song count and compare). The
/// lifetime here is only the backstop for servers that won't answer that.
public struct LibraryCache<Item: Codable & Sendable>: Sendable {
    private struct Payload: Codable {
        let owner: String
        let savedAt: Date
        let items: [Item]
    }

    private let fileName: String
    private let lifetime: TimeInterval

    public init(name: String, lifetime: TimeInterval = 14 * 24 * 60 * 60) {
        self.fileName = "\(name).json"
        self.lifetime = lifetime
    }

    private var url: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(fileName)
    }

    /// The saved library, or `nil` when there is none, it belongs to a
    /// different server or login, or it has gone stale.
    ///
    /// This is `nonisolated async` — nothing here is actor-isolated — so
    /// reading and decoding a file that runs to megabytes happens on the
    /// concurrent executor even though every caller is on the main actor.
    public func load(owner: String) async -> [Item]? {
        guard let url,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.owner == owner,
              Date().timeIntervalSince(payload.savedAt) < lifetime,
              !payload.items.isEmpty
        else { return nil }
        return payload.items
    }

    /// Saves the library. Fire-and-forget: a failed write only means the next
    /// launch syncs again. The task is created in this un-isolated scope, so
    /// encoding doesn't land on the caller's actor.
    public func save(_ items: [Item], owner: String) {
        let payload = Payload(owner: owner, savedAt: Date(), items: items)
        let url = url
        Task(priority: .utility) {
            guard let url, let data = try? JSONEncoder().encode(payload) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// How much disk this holds, for the Storage settings. `0` when empty.
    public var sizeInBytes: Int {
        guard let url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return 0 }
        return size
    }

    public func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
