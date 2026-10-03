import Foundation

/// One pinned thing and its place among the pins.
public struct CuePin: SyncedListElement {
    public var item: CueItem
    public var order: String
    /// When it was pinned or last moved.
    public var changedAt: Date

    public var id: String { item.key }

    public init(item: CueItem, order: String = OrderKey.first, changedAt: Date) {
        self.item = item
        self.order = order
        self.changedAt = changedAt
    }
}

/// What the person pinned to the top of their library: albums, playlists
/// (a service's or Cue's own), artists and stations, from any service, in
/// the order they put them. A new pin goes first.
///
/// A pin's title and artwork are what they were when it was pinned. A Cue
/// playlist's pin shows the playlist's current name and cover instead,
/// read from the playlist itself, so renaming one never has to touch the
/// pins.
public struct CuePins: Codable, Equatable, Sendable {
    public private(set) var list: SyncedList<CuePin>

    public static let empty = CuePins(list: SyncedList())

    public init(list: SyncedList<CuePin>) {
        self.list = list
    }

    public var items: [CueItem] { list.elements.map(\.item) }
    public var count: Int { list.count }
    public var isEmpty: Bool { list.isEmpty }

    public func isPinned(_ item: CueItem) -> Bool {
        list.contains(id: item.key)
    }

    /// Pins `item` first, or moves it first if it's pinned already.
    public mutating func pin(_ item: CueItem, at date: Date = .now) {
        list.insert([CuePin(item: item, changedAt: date)], at: 0, at: date)
    }

    public mutating func unpin(_ item: CueItem, at date: Date = .now) {
        unpin(key: item.key, at: date)
    }

    public mutating func unpin(key: String, at date: Date = .now) {
        list.remove(ids: [key], at: date)
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int, at date: Date = .now) {
        list.move(fromOffsets: source, toOffset: destination, at: date)
    }

    public func merged(with other: CuePins) -> CuePins {
        CuePins(list: list.merged(with: other.list))
    }
}
