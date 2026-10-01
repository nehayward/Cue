import Foundation

/// Lightweight per-group snapshot persisted to disk so a fresh launch can paint
/// last-known song/artist/artwork before the first network pulse completes.
struct CachedGroup: Codable {
    let coordinatorID: String
    let memberRoomIDs: [String]   // sorted
    let trackID: String
    let trackName: String
    let trackArtist: String
    let trackAlbum: String
    let trackArtworkURL: URL?
    let trackSonosAlbumArtURL: URL?
    let trackMusicService: MusicService
    let trackDuration: TimeInterval
    /// Last-known volumes, so sliders open at a real level instead of 0 while
    /// the first reads land. Optional so caches written before these fields
    /// existed still decode.
    var groupVolume: Double?
    var roomVolumes: [String: Double]?
}

struct GroupsCache: Codable {
    let groups: [CachedGroup]

    /// Same shape as `GroupRoom.topologyKey` aggregated as a `Set`.
    var topologySignature: Set<String> {
        Set(groups.map { "\($0.coordinatorID):\($0.memberRoomIDs.joined(separator: ","))" })
    }
}

enum GroupsCacheStore {
    private static let filename = "GroupsCache.json"

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent(filename)
    }

    static func read() -> GroupsCache? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GroupsCache.self, from: data)
    }

    static func write(_ cache: GroupsCache) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
