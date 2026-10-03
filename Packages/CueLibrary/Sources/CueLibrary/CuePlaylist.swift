import Foundation

/// A playlist that belongs to Cue rather than to any service. It can hold
/// songs from Apple Music, Plex, Subsonic and Files side by side, and it's
/// on all the person's devices.
///
/// Edits merge (`merged(with:)`): a song added on the iPhone while another
/// is moved on the Mac keeps both changes. The songs merge through
/// `SyncedList`. The name, notes and cover each keep their later write.
public struct CuePlaylist: Codable, Equatable, Identifiable, Sendable {
    public struct Entry: SyncedListElement {
        /// The entry's own id, not the song's: a playlist can hold one song
        /// twice.
        public let id: String
        public var item: CueItem
        public var order: String
        public var addedAt: Date
        public var changedAt: Date

        public init(id: String = UUID().uuidString, item: CueItem, order: String = OrderKey.first, addedAt: Date, changedAt: Date? = nil) {
            self.id = id
            self.item = item
            self.order = order
            self.addedAt = addedAt
            self.changedAt = changedAt ?? addedAt
        }
    }

    public enum Cover: Codable, Equatable, Sendable {
        /// The first four songs' artwork.
        case automatic
        /// One item's artwork (`CueItem.artwork`).
        case artwork(CueItem)
        /// A picture of the person's own, stored with the playlist under
        /// this name.
        case image(String)
    }

    public let id: String
    public private(set) var createdAt: Date
    public private(set) var name: Stamped<String>
    public private(set) var notes: Stamped<String>
    public private(set) var cover: Stamped<Cover>
    public private(set) var entries: SyncedList<Entry>

    public init(id: String = UUID().uuidString, name: String, items: [CueItem] = [], at date: Date = .now) {
        self.id = id
        self.createdAt = date
        self.name = Stamped(name, at: date)
        self.notes = Stamped("", at: date)
        self.cover = Stamped(.automatic, at: date)
        self.entries = SyncedList()
        append(items, at: date)
    }

    public var items: [CueItem] { entries.elements.map(\.item) }
    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    /// When anything in it last changed: the playlists list sorts by this.
    public var modifiedAt: Date {
        let stamps = [createdAt, name.at, notes.at, cover.at]
            + entries.elements.map(\.changedAt)
            + entries.removed.values
        return stamps.max() ?? createdAt
    }

    /// The pin, or a reference anywhere else, for this playlist.
    public var reference: CueItem {
        Self.reference(id: id, name: name.value)
    }

    public static func reference(id: String, name: String = "") -> CueItem {
        CueItem(source: .cue, kind: .playlist, id: id, title: name)
    }

    /// Whether it already has this song, for the "Already in playlist" hint.
    public func contains(_ item: CueItem) -> Bool {
        entries.elements.contains { $0.item.key == item.key }
    }

    // MARK: - Editing

    public mutating func rename(_ newName: String, at date: Date = .now) {
        name = Stamped(newName, at: date)
    }

    public mutating func setNotes(_ newNotes: String, at date: Date = .now) {
        notes = Stamped(newNotes, at: date)
    }

    public mutating func setCover(_ newCover: Cover, at date: Date = .now) {
        cover = Stamped(newCover, at: date)
    }

    /// Adds `items` to the end; returns their entries' ids.
    @discardableResult
    public mutating func append(_ items: [CueItem], at date: Date = .now) -> [String] {
        insert(items, at: entries.count, at: date)
    }

    /// Puts `items` in before the entry at `index`; returns their entries'
    /// ids.
    @discardableResult
    public mutating func insert(_ items: [CueItem], at index: Int, at date: Date = .now) -> [String] {
        let new = items.map { Entry(item: $0, addedAt: date) }
        entries.insert(new, at: index, at: date)
        return new.map(\.id)
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int, at date: Date = .now) {
        entries.move(fromOffsets: source, toOffset: destination, at: date)
    }

    public mutating func remove(atOffsets offsets: IndexSet, at date: Date = .now) {
        entries.remove(atOffsets: offsets, at: date)
    }

    public mutating func remove(entryIDs: some Sequence<String>, at date: Date = .now) {
        entries.remove(ids: entryIDs, at: date)
    }

    /// Puts another item in an entry's place: a person swapping a song
    /// for another version of it. Only people do this. Lookups and
    /// matches the app makes by itself are kept on the device, because a
    /// change here counts as an edit and would win over a removal made
    /// elsewhere.
    public mutating func replaceItem(entryID: String, with item: CueItem, at date: Date = .now) {
        entries.update(id: entryID, at: date) { $0.item = item }
    }

    // MARK: - Merging

    /// This playlist as both devices have it. `other` must be the same
    /// playlist (the same id); anything else leaves this one as it is.
    public func merged(with other: CuePlaylist) -> CuePlaylist {
        guard other.id == id else { return self }
        var merged = self
        merged.createdAt = min(createdAt, other.createdAt)
        merged.name = name.merged(with: other.name)
        merged.notes = notes.merged(with: other.notes)
        merged.cover = cover.merged(with: other.cover)
        merged.entries = entries.merged(with: other.entries)
        return merged
    }
}
