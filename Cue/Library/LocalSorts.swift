import Foundation
import SonosKit

/// Sort menu entries for a list Cue orders itself, because the service
/// gives it in another order, or none. Built once with the list's loader,
/// then one line per entry:
///
///     let favorites = LocalSorts { await service.favoritesShelf() }
///     favorites.byDate("Date Added") { service.dates(of: $0.id)?.added }
///     favorites.byName("Title") { $0.title }
///
/// Each entry reads the whole list and sorts it, so it's the list's only
/// page. Items without the value go last either way; ties keep the list's
/// own order. A date starts newest first (`defaultsToDescending`), which
/// the Order menu lists on top. On the main actor, where the services the
/// keys read live. Clic's `LocalSorts`, in Cue's direction: `descending`
/// is the order asked for, not a flip of the entry's own.
@MainActor
struct LocalSorts {
    let load: @MainActor () async -> [PlayableContent]

    init(load: @escaping @MainActor () async -> [PlayableContent]) {
        self.load = load
    }

    /// A – Z by a name, folded for case and accents.
    func byName(_ name: String, _ key: @escaping @MainActor (PlayableContent) -> String?) -> PlayableListSort {
        sort(name, ascendingLabel: "A – Z", descendingLabel: "Z – A", defaultsToDescending: false) {
            key($0).map(Self.folded)
        }
    }

    /// Newest first by a date as Apple writes them (`2022-08-06T02:18:57Z`,
    /// `2022-02-11`), which order as text.
    func byDate(_ name: String, _ key: @escaping @MainActor (PlayableContent) -> String?) -> PlayableListSort {
        sort(name, ascendingLabel: "Oldest First", descendingLabel: "Newest First", defaultsToDescending: true, key: key)
    }

    /// Newest first by a date.
    func byDate(_ name: String, _ key: @escaping @MainActor (PlayableContent) -> Date?) -> PlayableListSort {
        sort(name, ascendingLabel: "Oldest First", descendingLabel: "Newest First", defaultsToDescending: true, key: key)
    }

    private func sort<Key: Comparable>(
        _ name: String,
        ascendingLabel: String,
        descendingLabel: String,
        defaultsToDescending: Bool,
        key: @escaping @MainActor (PlayableContent) -> Key?
    ) -> PlayableListSort {
        let load = load
        return PlayableListSort(
            name: name,
            ascendingLabel: ascendingLabel,
            descendingLabel: descendingLabel,
            defaultsToDescending: defaultsToDescending
        ) { @MainActor offset, descending in
            guard offset == 0 else { return [] }
            return Self.sorted(await load(), descending: descending, by: key)
        }
    }

    /// `items` ordered by `key`, worked out once per item and compared with
    /// `<`: `localizedStandardCompare` in the comparator cost ~2 µs a call,
    /// 46 ms for ten thousand titles against 4 ms.
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
