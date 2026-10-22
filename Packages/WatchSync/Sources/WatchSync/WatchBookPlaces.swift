import Foundation

/// Where the listener is in a book: seconds into the whole book, its
/// length, whether it's finished, and when the place last moved. The fields
/// of MusicSearchKit's `AudiobookProgress`, which each device keeps its
/// places in; this is how one crosses to the other.
public struct WatchBookPlace: Codable, Equatable, Hashable, Sendable {
    public var position: TimeInterval
    public var duration: TimeInterval
    public var isFinished: Bool
    public var updatedAt: Date

    public init(position: TimeInterval, duration: TimeInterval, isFinished: Bool, updatedAt: Date) {
        self.position = position
        self.duration = duration
        self.isFinished = isFinished
        self.updatedAt = updatedAt
    }

    /// Whether this place wins over `other`: the one that moved last. Two
    /// readings of one moment (the same place, told both ways) settle the
    /// same on both devices: the one further in.
    public func supersedes(_ other: WatchBookPlace) -> Bool {
        if updatedAt != other.updatedAt { return updatedAt > other.updatedAt }
        if position != other.position { return position > other.position }
        if isFinished != other.isFinished { return isFinished }
        return duration > other.duration
    }
}

/// Each book's place, by its pick's key (`WatchPick.key`). Both devices
/// send the places of the books picked for the watch along with the picks
/// (`WatchSyncMessage`), and merge what arrives: for each book the place
/// that moved last wins, so a book listened to on one device picks up on
/// the other where it was left. Each side sends back only when it holds a
/// place the other lacks or would take (`hasNews(for:)`), which settles in
/// one round.
public struct WatchBookPlaces: Codable, Equatable, Sendable {
    public private(set) var places: [String: WatchBookPlace]

    public static let empty = WatchBookPlaces(places: [:])

    public init(places: [String: WatchBookPlace]) {
        self.places = places
    }

    public subscript(key: String) -> WatchBookPlace? {
        places[key]
    }

    public var isEmpty: Bool { places.isEmpty }

    /// Keeps `place` for the book unless the one held moved later. True
    /// when it was kept.
    @discardableResult
    public mutating func record(_ place: WatchBookPlace, for key: String) -> Bool {
        if let held = places[key], !place.supersedes(held) { return false }
        places[key] = place
        return true
    }

    public mutating func remove(key: String) {
        places[key] = nil
    }

    /// Both sides' places together, each book's latest.
    public func merged(with other: WatchBookPlaces) -> WatchBookPlaces {
        var merged = self
        for (key, place) in other.places {
            merged.record(place, for: key)
        }
        return merged
    }

    /// Only the books with these keys: those picked for the watch.
    public func restricted(to keys: Set<String>) -> WatchBookPlaces {
        WatchBookPlaces(places: places.filter { keys.contains($0.key) })
    }

    /// Whether this holds a place `other` is missing, or one newer than
    /// `other`'s: what the other side has yet to hear.
    public func hasNews(for other: WatchBookPlaces) -> Bool {
        places.contains { key, place in
            guard let theirs = other.places[key] else { return true }
            return place.supersedes(theirs)
        }
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) throws -> WatchBookPlaces {
        try JSONDecoder().decode(WatchBookPlaces.self, from: data)
    }
}
