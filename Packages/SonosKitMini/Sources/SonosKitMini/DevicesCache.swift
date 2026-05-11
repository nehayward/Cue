import Foundation

/// Lightweight per-device snapshot persisted to disk so a fresh launch can paint
/// last-known song/artist/artwork before the first network pulse completes.
struct CachedDevice: Codable {
    let deviceID: String
    let memberRoomIDs: [String]   // sorted
    let trackID: String
    let trackURI: String
    let trackName: String
    let trackArtist: String
    let trackAlbum: String
    let trackArtworkURL: URL?
    let trackSonosAlbumArtURL: URL?
    let trackMusicService: SonosMusicServiceType
    let trackDurationSeconds: Double
}

struct DevicesCache: Codable {
    let devices: [CachedDevice]

    /// Stable id-only fingerprint for detecting topology changes (device + sorted member ids).
    var topologySignature: Set<String> {
        Set(devices.map { "\($0.deviceID):\($0.memberRoomIDs.joined(separator: ","))" })
    }
}

enum DevicesCacheStore {
    private static let filename = "DevicesCache.json"

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent(filename)
    }

    static func read() -> DevicesCache? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DevicesCache.self, from: data)
    }

    static func write(_ cache: DevicesCache) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
