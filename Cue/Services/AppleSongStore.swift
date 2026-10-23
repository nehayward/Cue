import Foundation
import MusicKit

/// The Apple Music `Song`s the device player has looked up, kept on disk so
/// a song Cue has seen before arms with no catalog request — which is what
/// lets songs the Music app has downloaded start in airplane mode.
///
/// One file per song, read only when that song is asked for, off the main
/// thread. It replaces a single file of every song ever looked up, decoded
/// whole on the main thread at launch: a `Song` takes over a millisecond to
/// decode and about 25 KB once decoded, so 350 songs held up the launch by
/// half a second and kept 9 MB in memory for good, more with every song
/// played, and each new song wrote the whole file out again.
actor AppleSongStore {
    static let shared = AppleSongStore()

    /// The most songs kept; past it, the ones used longest ago go. About
    /// 1.5 KB each.
    private static let limit = 3000

    private let directory: URL?
    private var isPrepared = false
    private var storedSinceTrim = 0

    private init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AppleSongs", isDirectory: true)
    }

    /// The songs kept under `keys`. A key with none is left out.
    func songs(for keys: [String]) -> [String: Song] {
        prepare()
        guard let directory else { return [:] }
        let decoder = JSONDecoder()
        let now = Date()
        var found: [String: Song] = [:]
        for key in keys {
            let url = Self.fileURL(for: key, in: directory)
            guard let data = try? Data(contentsOf: url),
                  let song = try? decoder.decode(Song.self, from: data) else { continue }
            found[key] = song
            // Used now, so the trim keeps it.
            try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
        }
        return found
    }

    func store(_ songs: [String: Song]) {
        prepare()
        guard let directory, !songs.isEmpty else { return }
        let encoder = JSONEncoder()
        for (key, song) in songs {
            guard let data = try? encoder.encode(song) else { continue }
            try? data.write(to: Self.fileURL(for: key, in: directory), options: .atomic)
        }
        storedSinceTrim += songs.count
        if storedSinceTrim >= 200 {
            trim()
        }
    }

    /// Makes the folder, and moves songs out of the single file earlier
    /// builds kept, once per launch.
    func prepare() {
        guard !isPrepared, let directory else { return }
        isPrepared = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = directory.deletingLastPathComponent().appendingPathComponent("AppleSongCache.json")
        guard let data = try? Data(contentsOf: legacy) else { return }
        // Split as plain JSON: each value is a song exactly as `Song`
        // encodes itself, so nothing needs decoding here.
        if let songs = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, song) in songs {
                guard let songData = try? JSONSerialization.data(withJSONObject: song) else { continue }
                try? songData.write(to: Self.fileURL(for: key, in: directory), options: .atomic)
            }
        }
        try? FileManager.default.removeItem(at: legacy)
        trim()
    }

    /// Deletes the songs used longest ago, past `limit`.
    private func trim() {
        storedSinceTrim = 0
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey]),
              files.count > Self.limit else { return }
        let dated = files.map { url in
            (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for (url, _) in dated.sorted(by: { $0.1 < $1.1 }).prefix(files.count - Self.limit) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Keys are catalog ids and `library:` ids: kept to characters safe in a
    /// file name.
    private static func fileURL(for key: String, in directory: URL) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let name = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }
}
