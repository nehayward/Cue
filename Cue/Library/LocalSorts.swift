import Foundation
import SonosKit

/// Sort menu entries for a list Cue orders itself, because the service
/// gives it in another order. Built once with the list's loader, then one
/// line per entry:
///
///     let favorites = LocalSorts { await service.subsonicFavorites() }
///     favorites.byDate("Date Favorited") { service.subsonicFavoriteDate(of: $0.id) }
///     favorites.byName("Title") { $0.title }
///
/// Each entry reads the whole list and sorts it, so it's the list's only
/// page. Items without the value go last either way; ties keep the list's
/// own order. On the main actor, where the services the keys read live.
@MainActor
struct LocalSorts {
    let load: @MainActor () async -> [PlayableContent]

    init(load: @escaping @MainActor () async -> [PlayableContent]) {
        self.load = load
    }

    /// A – Z by a name, folded for case and accents.
    func byName(_ name: String, _ key: @escaping @MainActor (PlayableContent) -> String?) -> PlayableListSort {
        sort(name, ascendingLabel: "A – Z", descendingLabel: "Z – A", startsDescending: false) {
            key($0).map(Self.folded)
        }
    }

    /// Newest first by a date as a server writes it in ISO 8601
    /// (`2024-03-01T10:00:00Z`), which orders as text.
    func byDate(_ name: String, _ key: @escaping @MainActor (PlayableContent) -> String?) -> PlayableListSort {
        sort(name, ascendingLabel: "Newest First", descendingLabel: "Oldest First", startsDescending: true, key: key)
    }

    /// The menu's first direction is the order's natural one, so a date's
    /// is newest first: `startsDescending` turns the sort, not the menu.
    private func sort<Key: Comparable>(
        _ name: String,
        ascendingLabel: String,
        descendingLabel: String,
        startsDescending: Bool,
        key: @escaping @MainActor (PlayableContent) -> Key?
    ) -> PlayableListSort {
        let load = load
        return PlayableListSort(name: name, ascendingLabel: ascendingLabel, descendingLabel: descendingLabel) { @MainActor offset, reversed in
            guard offset == 0 else { return [] }
            return Self.sorted(await load(), descending: startsDescending != reversed, by: key)
        }
    }

    /// `items` ordered by `key`, worked out once per item and compared with
    /// `<`, rather than worked out again in every comparison.
    static func sorted<Key: Comparable>(
        _ items: [PlayableContent],
        descending: Bool,
        by key: @MainActor (PlayableContent) -> Key?
    ) -> [PlayableContent] {
        let keyed = items.enumerated().map { (offset: $0.offset, item: $0.element, key: key($0.element)) }
        return keyed.sorted { a, b in
            switch (a.key, b.key) {
            case (nil, nil): return a.offset < b.offset
            case (nil, _): return false
            case (_, nil): return true
            case let (x?, y?):
                guard x != y else { return a.offset < b.offset }
                return descending ? x > y : x < y
            }
        }
        .map(\.item)
    }

    /// A name as it sorts: case, accents and width folded away.
    nonisolated static func folded(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
