import Defaults
import Foundation
import MusicSearchKit
import Observation
import SwiftUI

/// A provider in the tab view and which of its collections are tabs.
struct TabProvider: Codable, Hashable, Identifiable {
    var service: MediaSearchService
    /// The collections shown as tabs, kept in the provider's canonical
    /// order (`tabCollections`) whatever order they were switched on in.
    var collections: [ProviderCollection]

    var id: MediaSearchService { service }

    init(service: MediaSearchService) {
        self.service = service
        self.collections = service.defaultTabCollections
    }

    func isEnabled(_ collection: ProviderCollection) -> Bool {
        collections.contains(collection)
    }

    mutating func toggle(_ collection: ProviderCollection) {
        var enabled = Set(collections)
        if enabled.contains(collection) {
            enabled.remove(collection)
        } else {
            enabled.insert(collection)
        }
        collections = service.tabCollections.filter { enabled.contains($0) }
    }
}

/// The providers the user has added to the tab view, in order, and the
/// collections each one shows. Every provider is a tab of its own; on iPad
/// and Mac it is also a sidebar section with those collections as tabs.
/// Persisted on this device only, like the library section order — the
/// tab bar is a per-device arrangement.
@MainActor
@Observable
final class TabProviderStore {
    static let shared = TabProviderStore()

    private(set) var providers: [TabProvider] {
        didSet { save() }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: AppStorageKeys.tabProviders),
           let decoded = try? JSONDecoder().decode([TabProvider].self, from: data) {
            providers = decoded
        } else if let raw = defaults.stringArray(forKey: AppStorageKeys.tabProviders) {
            // The first build stored bare service names; they become
            // providers with the default collections.
            providers = raw.compactMap(MediaSearchService.init(rawValue:)).map(TabProvider.init(service:))
        } else {
            providers = []
        }
    }

    func provider(for service: MediaSearchService) -> TabProvider? {
        providers.first { $0.service == service }
    }

    func contains(_ service: MediaSearchService) -> Bool {
        provider(for: service) != nil
    }

    func add(_ service: MediaSearchService) {
        guard service.canBeTab, !contains(service) else { return }
        providers.append(TabProvider(service: service))
    }

    func remove(_ service: MediaSearchService) {
        providers.removeAll { $0.service == service }
    }

    func remove(atOffsets offsets: IndexSet) {
        providers.remove(atOffsets: offsets)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        providers.move(fromOffsets: source, toOffset: destination)
    }

    func toggle(_ collection: ProviderCollection, for service: MediaSearchService) {
        guard let index = providers.firstIndex(where: { $0.service == service }) else { return }
        providers[index].toggle(collection)
    }

    /// The added providers that are switched on in Services. A provider the
    /// user turned off there keeps its place in the list, so switching it
    /// back on brings its tabs back where they were.
    func visibleProviders(enabledIn coreFeatures: CoreFeatures) -> [TabProvider] {
        providers.filter { coreFeatures.isEnabled($0.service) }
    }

    /// The providers that could be added: switched on in Services, with
    /// collections to browse, and not in the tab view yet.
    func availableProviders(enabledIn coreFeatures: CoreFeatures) -> [MediaSearchService] {
        MediaSearchService.allCases.filter { service in
            service.canBeTab && coreFeatures.isEnabled(service) && !contains(service)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        defaults.set(data, forKey: AppStorageKeys.tabProviders)
    }
}
