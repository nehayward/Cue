import Foundation

/// The synced song library, kept on disk so the sync is genuinely one-time
/// rather than once per launch.
///
/// It lives in Caches because it is derived data — the system may reclaim it,
/// and the only cost is syncing again. Whether it is still current is decided
/// by the caller, which compares the song count against the server's own
/// (`getScanStatus`); the timestamp here is the fallback for servers that
/// don't answer that.
extension SubsonicAPI {
    private struct CachedLibrary: Codable {
        let server: String
        let username: String
        let savedAt: Date
        let songs: [SubsonicSong]
    }

    /// How long a cache is trusted when the server won't report a count to
    /// check it against.
    private static let cacheLifetime: TimeInterval = 14 * 24 * 60 * 60

    private static var cacheURL: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SubsonicLibrary.json")
    }

    /// The library saved for the current server, or `nil` when there is none,
    /// it belongs to a different server or login, or it has gone stale.
    /// Decoding happens off the main thread — the file runs to megabytes.
    public func cachedSongLibrary() async -> [SubsonicSong]? {
        let server = serverAddress
        let username = self.username
        return await Task.detached(priority: .userInitiated) {
            guard let url = Self.cacheURL,
                  let data = try? Data(contentsOf: url),
                  let cached = try? JSONDecoder().decode(CachedLibrary.self, from: data),
                  cached.server == server,
                  cached.username == username,
                  Date().timeIntervalSince(cached.savedAt) < Self.cacheLifetime,
                  !cached.songs.isEmpty
            else { return nil }
            return cached.songs
        }.value
    }

    /// Saves the library for the current server. Fire-and-forget: a failed
    /// write only means the next launch syncs again.
    public func cacheSongLibrary(_ songs: [SubsonicSong]) {
        let cached = CachedLibrary(
            server: serverAddress,
            username: username,
            savedAt: Date(),
            songs: songs
        )
        Task.detached(priority: .utility) {
            guard let url = Self.cacheURL, let data = try? JSONEncoder().encode(cached) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Removes the saved library — on disconnect (it is the user's own
    /// library metadata, and the server it came from is gone) and whenever a
    /// refresh should really re-read the server.
    public func clearCachedSongLibrary() {
        guard let url = Self.cacheURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
