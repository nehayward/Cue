import Foundation

/// A server the watch downloads from.
public enum WatchSource: String, Codable, CaseIterable, Hashable, Sendable {
    case plex, subsonic

    public var title: String {
        switch self {
        case .plex: "Plex"
        case .subsonic: "Subsonic"
        }
    }
}

/// Something chosen to be on the watch: an album, playlist, artist or song
/// on a Plex or Subsonic server, by its id. The watch looks it up itself
/// (MusicSearchKit) and downloads its songs — the pick is all that crosses
/// between the devices.
public struct WatchPick: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case album, playlist, artist, song
    }

    public let source: WatchSource
    public let kind: Kind
    /// The id the iPhone's library gives it: a Plex item's Sonos-style id,
    /// a Subsonic id.
    public let id: String
    public var title: String
    public var subtitle: String
    public var artworkURL: URL?
    public var addedAt: Date

    public var key: String { WatchKeys.pick(kind: kind, source: source, id: id) }

    public init(source: WatchSource, kind: Kind, id: String, title: String, subtitle: String = "", artworkURL: URL? = nil, addedAt: Date = .now) {
        self.source = source
        self.kind = kind
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.addedAt = addedAt
    }
}

/// What's chosen to be on the watch, newest first. Either device changes it
/// — the iPhone from Add to Apple Watch, the watch from Add Music — and they
/// merge rather than overwrite: for each pick the later of its last add and
/// its last removal wins (a removal is kept as a dated tombstone), so
/// changes made apart, or at once, all survive. Each side sends its picks
/// when they change, merges what arrives, and sends back only when the
/// other side was missing something — which settles in one round.
public struct WatchPicks: Codable, Equatable, Sendable {
    public private(set) var items: [WatchPick]
    /// When each pick was last removed, by key.
    public private(set) var removed: [String: Date]

    public static let empty = WatchPicks(items: [], removed: [:])

    /// Tombstones older than this are dropped: by then both sides have heard.
    public static let tombstoneLifetime: TimeInterval = 180 * 24 * 60 * 60

    public init(items: [WatchPick], removed: [String: Date]) {
        self.items = items
        self.removed = removed
    }

    public func pick(key: String) -> WatchPick? {
        items.first { $0.key == key }
    }

    public func contains(key: String) -> Bool {
        pick(key: key) != nil
    }

    /// Adds a pick at the front, or moves it there, as of `date`.
    public mutating func add(_ pick: WatchPick, at date: Date = .now) {
        var pick = pick
        pick.addedAt = date
        items.removeAll { $0.key == pick.key }
        items.append(pick)
        items.sort(by: Self.newestFirst)
        removed[pick.key] = nil
    }

    public mutating func remove(key: String, at date: Date = .now) {
        items.removeAll { $0.key == key }
        removed[key] = date
        pruneTombstones(now: date)
    }

    public mutating func removeAll(at date: Date = .now) {
        for item in items {
            removed[item.key] = date
        }
        items.removeAll()
        pruneTombstones(now: date)
    }

    /// Both sides' picks together: each pick as of its latest add, unless
    /// it was removed at or after that.
    public func merged(with other: WatchPicks) -> WatchPicks {
        var latestAdd: [String: WatchPick] = [:]
        for pick in items + other.items {
            if let known = latestAdd[pick.key], known.addedAt >= pick.addedAt { continue }
            latestAdd[pick.key] = pick
        }
        let latestRemoval = removed.merging(other.removed) { max($0, $1) }
        let kept = latestAdd.values.filter { pick in
            guard let removedAt = latestRemoval[pick.key] else { return true }
            return pick.addedAt > removedAt
        }
        let tombstones = latestRemoval.filter { key, removedAt in
            guard let pick = latestAdd[key] else { return true }
            return removedAt >= pick.addedAt
        }
        return WatchPicks(
            items: kept.sorted(by: Self.newestFirst),
            removed: tombstones
        )
    }

    /// One order for both sides, so equal picks compare equal.
    private static func newestFirst(_ lhs: WatchPick, _ rhs: WatchPick) -> Bool {
        (lhs.addedAt, lhs.key) > (rhs.addedAt, rhs.key)
    }

    private mutating func pruneTombstones(now: Date) {
        removed = removed.filter { now.timeIntervalSince($0.value) < Self.tombstoneLifetime }
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) throws -> WatchPicks {
        try JSONDecoder().decode(WatchPicks.self, from: data)
    }
}
