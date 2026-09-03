import Defaults
import Foundation
import MusicSearchKit
import Observation
import SwiftUI

/// The providers the user has added to the tab view, in order. Each one is a
/// tab of its own, and on iPad and Mac a sidebar section split into its
/// collections. Persisted on this device only, like the library section
/// order — the tab bar is a per-device arrangement.
@MainActor
@Observable
final class TabProviderStore {
    static let shared = TabProviderStore()

    private(set) var providers: [MediaSearchService] {
        didSet { save() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.stringArray(forKey: AppStorageKeys.tabProviders) ?? []
        providers = raw.compactMap(MediaSearchService.init(rawValue:))
    }

    @ObservationIgnored private let defaults: UserDefaults

    func contains(_ service: MediaSearchService) -> Bool {
        providers.contains(service)
    }

    func add(_ service: MediaSearchService) {
        guard service.canBeTab, !providers.contains(service) else { return }
        providers.append(service)
    }

    func remove(_ service: MediaSearchService) {
        providers.removeAll { $0 == service }
    }

    func toggle(_ service: MediaSearchService) {
        if contains(service) {
            remove(service)
        } else {
            add(service)
        }
    }

    func remove(atOffsets offsets: IndexSet) {
        providers.remove(atOffsets: offsets)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        providers.move(fromOffsets: source, toOffset: destination)
    }

    /// The added providers that are switched on in Services. A provider the
    /// user turned off there keeps its place in the list, so switching it
    /// back on brings its tab back where it was.
    func visibleProviders(enabledIn coreFeatures: CoreFeatures) -> [MediaSearchService] {
        providers.filter { coreFeatures.isEnabled($0) }
    }

    /// The providers that could be added: switched on in Services, able to
    /// browse, and not in the tab view yet.
    func availableProviders(enabledIn coreFeatures: CoreFeatures) -> [MediaSearchService] {
        MediaSearchService.allCases.filter { service in
            service.canBeTab && coreFeatures.isEnabled(service) && !providers.contains(service)
        }
    }

    private func save() {
        defaults.set(providers.map(\.rawValue), forKey: AppStorageKeys.tabProviders)
    }
}
