import Foundation

/// Everything that's Cue's own and follows the person between devices:
/// their playlists and their pins.
///
/// This one value is what goes to the watch, and what tests merge. On the
/// device and in iCloud each playlist is saved on its own, so an edit
/// encodes only its own playlist: a 5,000-song playlist takes about 70 ms
/// to encode, and a whole library of them far longer. iCloud carries one
/// record per playlist and one for the pins, merged with the same
/// functions.
public struct CueLibrary: Codable, Equatable, Sendable {
    public private(set) var playlists: [String: CuePlaylist]
    /// When each deleted playlist was deleted, by id.
    public private(set) var deletedPlaylists: [String: Date]
    public var pins: CuePins

    public static let empty = CueLibrary(playlists: [:], deletedPlaylists: [:], pins: .empty)

    public init(playlists: [String: CuePlaylist], deletedPlaylists: [String: Date], pins: CuePins) {
        self.playlists = playlists
        self.deletedPlaylists = deletedPlaylists
        self.pins = pins
    }

    /// The last changed first: the Playlists screen's default order.
    public var recentPlaylists: [CuePlaylist] {
        playlists.values
            .map { (playlist: $0, modifiedAt: $0.modifiedAt) }
            .sorted { ($0.modifiedAt, $0.playlist.id) > ($1.modifiedAt, $1.playlist.id) }
            .map(\.playlist)
    }

    public func playlist(id: String) -> CuePlaylist? {
        playlists[id]
    }

    // MARK: - Editing

    @discardableResult
    public mutating func createPlaylist(named name: String, with items: [CueItem] = [], at date: Date = .now) -> CuePlaylist {
        let playlist = CuePlaylist(name: name, items: items, at: date)
        playlists[playlist.id] = playlist
        return playlist
    }

    /// Changes a playlist in place with its own editing calls.
    public mutating func updatePlaylist(id: String, _ change: (inout CuePlaylist) -> Void) {
        guard var playlist = playlists[id] else { return }
        change(&playlist)
        playlists[id] = playlist
    }

    /// Takes in a playlist as another device has it, merged with this
    /// device's copy.
    public mutating func receive(_ playlist: CuePlaylist) {
        let merged = playlists[playlist.id].map { $0.merged(with: playlist) } ?? playlist
        if let deletedAt = deletedPlaylists[playlist.id], deletedAt >= merged.modifiedAt {
            return
        }
        deletedPlaylists[playlist.id] = nil
        playlists[playlist.id] = merged
    }

    /// Deletes a playlist and its pin.
    public mutating func deletePlaylist(id: String, at date: Date = .now) {
        playlists[id] = nil
        pins.unpin(CuePlaylist.reference(id: id), at: date)
        deletedPlaylists[id] = date
        pruneTombstones(now: date)
    }

    public mutating func pruneTombstones(now: Date) {
        deletedPlaylists = deletedPlaylists.filter {
            now.timeIntervalSince($0.value) < SyncedList<CuePin>.tombstoneLifetime
        }
    }

    // MARK: - Merging

    /// Both sides together. A deleted playlist stays deleted unless it was
    /// changed after it was deleted.
    public func merged(with other: CueLibrary) -> CueLibrary {
        var merged = playlists
        for (id, playlist) in other.playlists {
            merged[id] = merged[id].map { $0.merged(with: playlist) } ?? playlist
        }
        let deletions = deletedPlaylists.merging(other.deletedPlaylists) { max($0, $1) }
        let kept = merged.filter { id, playlist in
            guard let deletedAt = deletions[id] else { return true }
            return playlist.modifiedAt > deletedAt
        }
        let tombstones = deletions.filter { id, deletedAt in
            guard let playlist = merged[id] else { return true }
            return deletedAt >= playlist.modifiedAt
        }
        return CueLibrary(playlists: kept, deletedPlaylists: tombstones, pins: pins.merged(with: other.pins))
    }

    // MARK: - Coding

    public func encoded() throws -> Data {
        try CueLibraryCoding.encode(self)
    }

    public static func decoded(from data: Data) throws -> CueLibrary {
        try CueLibraryCoding.decode(CueLibrary.self, from: data)
    }
}

/// JSON, packed. A playlist is mostly repeated strings, so it shrinks
/// several times over, which matters against CloudKit's 1 MB per record.
/// LZFSE where the system has it, plain elsewhere (the Linux test runs);
/// a leading byte says which, as in `WatchSyncMessage`.
public enum CueLibraryCoding {
    private enum Packing: UInt8 {
        case plain = 0
        case lzfse = 1
    }

    public enum Failure: Error {
        case unreadable
    }

    public static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return pack(try encoder.encode(value))
    }

    public static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        guard let json = unpack(data) else { throw Failure.unreadable }
        return try JSONDecoder().decode(type, from: json)
    }

    static func pack(_ data: Data) -> Data {
        #if canImport(Darwin)
        if let compressed = try? (data as NSData).compressed(using: .lzfse) as Data {
            return Data([Packing.lzfse.rawValue]) + compressed
        }
        #endif
        return Data([Packing.plain.rawValue]) + data
    }

    static func unpack(_ packed: Data) -> Data? {
        guard let first = packed.first, let packing = Packing(rawValue: first) else { return nil }
        let body = packed.dropFirst()
        switch packing {
        case .plain:
            return Data(body)
        case .lzfse:
            #if canImport(Darwin)
            return try? (Data(body) as NSData).decompressed(using: .lzfse) as Data
            #else
            return nil
            #endif
        }
    }
}
