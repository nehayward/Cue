import SwiftUI
import SonosKit
import MusicSearchKit


@Observable
final class GenericFilter<Item: Filterable>: Hashable, Identifiable {
    let filter: Item
    
    @ObservationIgnored
    public var isFiltered: Bool {
        get {
            access(keyPath: \.isFiltered)
            return UserDefaults.standard.bool(forKey: filter.name)
        }
        set {
            withMutation(keyPath: \.isFiltered) {
                UserDefaults.standard.set(newValue, forKey: filter.name)
            }
        }
    }
    var notFiltered: Bool { !isFiltered }

    init(filter: Item) {
        self.filter = filter
    }

    nonisolated static func == (lhs: GenericFilter, rhs: GenericFilter) -> Bool { lhs === rhs}

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

protocol Filterable {
    var name: String { get }
}

// Conformance
extension PlexLibrarySection: Filterable {
    public var name: String { title }
}
