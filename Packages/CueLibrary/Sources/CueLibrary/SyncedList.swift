import Foundation

/// An element of a `SyncedList`: something with an id, a place in the list
/// and the time it last changed.
public protocol SyncedListElement: Codable, Equatable, Sendable {
    var id: String { get }
    /// Its `OrderKey`.
    var order: String { get set }
    /// When it was last added, moved or changed: what its merge goes by.
    var changedAt: Date { get set }
}

/// A list that several devices edit apart and then merge. Both a
/// playlist's songs and the pins take this shape.
///
/// Each element carries its own place (`OrderKey`) and the time it last
/// changed, and a removal is kept as a dated tombstone. A merge takes, for
/// each id, the side that changed it last, and drops it if it was removed
/// at or after that. So additions, moves and removals made on different
/// devices all survive, and the merge gives the same list whichever side
/// does it. `WatchPicks` works the same way, but without an order.
///
/// Elements are kept sorted by their key, then their id, so two elements
/// put in the same place on two devices at once still sort the same way
/// everywhere. The next edit there gives them keys of their own.
public struct SyncedList<Element: SyncedListElement>: Codable, Equatable, Sendable {
    /// In order.
    public private(set) var elements: [Element]
    /// When each removed element was removed, by id.
    public private(set) var removed: [String: Date]

    /// Tombstones older than this are dropped: by then every device has
    /// heard. A device that was away longer and still holds unsent edits
    /// could bring a removed element back, which is why a fetched record
    /// replaces the local copy outright unless a local edit is waiting
    /// (see `Ideas/cue-playlists-and-pins.md`).
    public static var tombstoneLifetime: TimeInterval { 180 * 24 * 60 * 60 }

    public init(elements: [Element] = [], removed: [String: Date] = [:]) {
        self.elements = elements.sorted(by: Self.inOrder)
        self.removed = removed
    }

    public var count: Int { elements.count }
    public var isEmpty: Bool { elements.isEmpty }

    public func contains(id: String) -> Bool {
        index(of: id) != nil
    }

    public func element(id: String) -> Element? {
        index(of: id).map { elements[$0] }
    }

    public func index(of id: String) -> Int? {
        elements.firstIndex { $0.id == id }
    }

    // MARK: - Editing

    /// Puts `new` in at `index`, in the order given, as of `date`. An
    /// element already in the list moves there instead of appearing twice.
    public mutating func insert(_ new: [Element], at index: Int, at date: Date = .now) {
        var seen = Set<String>()
        let new = new.filter { seen.insert($0.id).inserted }
        guard !new.isEmpty else { return }
        var target = min(max(index, 0), elements.count)
        target -= elements[..<target].filter { seen.contains($0.id) }.count
        elements.removeAll { seen.contains($0.id) }
        place(new, at: target, date: date)
        for id in seen {
            removed[id] = nil
        }
    }

    public mutating func append(_ new: [Element], at date: Date = .now) {
        insert(new, at: elements.count, at: date)
    }

    /// Moves the elements at `source` to before `destination`, as
    /// `onMove` reports it (`destination` counts the moved elements too).
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int, at date: Date = .now) {
        let offsets = source.filter { elements.indices.contains($0) }.sorted()
        guard let firstOffset = offsets.first else { return }
        let target = min(max(destination, 0), elements.count) - offsets.filter { $0 < destination }.count
        // A block dropped where it already is: nothing changed, so nothing
        // should be stamped as changed.
        let isContiguous = offsets.last! - firstOffset == offsets.count - 1
        if isContiguous, target == firstOffset { return }
        let moving = offsets.map { elements[$0] }
        let ids = Set(moving.map(\.id))
        elements.removeAll { ids.contains($0.id) }
        place(moving, at: target, date: date)
    }

    public mutating func remove(ids: some Sequence<String>, at date: Date = .now) {
        let ids = Set(ids)
        guard !ids.isEmpty else { return }
        elements.removeAll { ids.contains($0.id) }
        for id in ids {
            removed[id] = date
        }
        pruneTombstones(now: date)
    }

    public mutating func remove(atOffsets offsets: IndexSet, at date: Date = .now) {
        remove(ids: offsets.filter { elements.indices.contains($0) }.map { elements[$0].id }, at: date)
    }

    public mutating func removeAll(at date: Date = .now) {
        remove(ids: elements.map(\.id), at: date)
    }

    /// Changes an element where it stands, as of `date`.
    public mutating func update(id: String, at date: Date = .now, _ change: (inout Element) -> Void) {
        guard let index = index(of: id) else { return }
        var element = elements[index]
        let order = element.order
        change(&element)
        element.order = order
        element.changedAt = date
        elements[index] = element
    }

    public mutating func pruneTombstones(now: Date) {
        removed = removed.filter { now.timeIntervalSince($0.value) < Self.tombstoneLifetime }
    }

    // MARK: - Merging

    /// Both sides together: each element as its side that changed it last
    /// has it, unless it was removed at or after that.
    public func merged(with other: SyncedList) -> SyncedList {
        var latest: [String: Element] = [:]
        for element in elements + other.elements {
            if let known = latest[element.id], !Self.isLater(element, than: known) { continue }
            latest[element.id] = element
        }
        let latestRemoval = removed.merging(other.removed) { max($0, $1) }
        let kept = latest.values.filter { element in
            guard let removedAt = latestRemoval[element.id] else { return true }
            return element.changedAt > removedAt
        }
        let tombstones = latestRemoval.filter { id, removedAt in
            guard let element = latest[id] else { return true }
            return removedAt >= element.changedAt
        }
        return SyncedList(elements: Array(kept), removed: tombstones)
    }

    /// Which of two versions of one element a merge keeps: the later
    /// change, and between two made at the same moment, the same one on
    /// every device.
    private static func isLater(_ element: Element, than known: Element) -> Bool {
        if element.changedAt != known.changedAt {
            return element.changedAt > known.changedAt
        }
        if element.order != known.order {
            return OrderKey.precedes(known.order, element.order)
        }
        return TieBreak.isGreater(element, than: known)
    }

    private static func inOrder(_ lhs: Element, _ rhs: Element) -> Bool {
        if lhs.order != rhs.order {
            return OrderKey.precedes(lhs.order, rhs.order)
        }
        return lhs.id.utf8.lexicographicallyPrecedes(rhs.id.utf8)
    }

    // MARK: - Placing

    /// Gives `moving` keys between the neighbours at `index` and puts them
    /// there.
    private mutating func place(_ moving: [Element], at index: Int, date: Date) {
        let lower = index > 0 ? elements[index - 1].order : nil
        // Elements that share the lower neighbour's key (two devices put
        // something in one place at once) leave no room between them, so
        // they take new keys along with what's being placed.
        var end = index
        if let lower {
            while end < elements.count, !OrderKey.precedes(lower, elements[end].order) {
                end += 1
            }
        }
        let upper = end < elements.count ? elements[end].order : nil
        var placed = moving + elements[index..<end]
        guard let keys = try? OrderKey.keys(between: lower, upper, count: placed.count) else {
            // A neighbour's key this build can't read: lay the whole list
            // out afresh rather than lose the edit.
            elements.insert(contentsOf: moving, at: index)
            renumber(at: date)
            return
        }
        for offset in placed.indices {
            placed[offset].order = keys[offset]
            placed[offset].changedAt = date
        }
        elements.replaceSubrange(index..<end, with: placed)
        elements.sort(by: Self.inOrder)
    }

    /// Fresh keys for every element, in the order they stand.
    private mutating func renumber(at date: Date) {
        guard let keys = try? OrderKey.keys(between: nil, nil, count: elements.count) else { return }
        for offset in elements.indices {
            elements[offset].order = keys[offset]
            elements[offset].changedAt = date
        }
    }

    // MARK: - Coding

    private enum CodingKeys: String, CodingKey {
        case elements, removed
    }

    /// Sorted on the way in, so a list from another device compares equal
    /// to the same list made here.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            elements: try container.decode([Element].self, forKey: .elements),
            removed: try container.decodeIfPresent([String: Date].self, forKey: .removed) ?? [:]
        )
    }
}

/// Picks one of two things made at the same moment on two devices, the same
/// one everywhere: the one whose JSON sorts last.
enum TieBreak {
    static func isGreater<Value: Encodable>(_ value: Value, than other: Value) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let lhs = (try? encoder.encode(value)) ?? Data()
        let rhs = (try? encoder.encode(other)) ?? Data()
        return rhs.lexicographicallyPrecedes(lhs)
    }
}
