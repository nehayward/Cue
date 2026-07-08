import Foundation
import MusicSearchKit

/// The search's selected services as ONE ordered list — primary first, up to
/// `maxCount`. Replaces the old split storage (primary in `mediaService`,
/// extras in `searchAlsoServices`); old values are deliberately not migrated,
/// the selection resets once and users re-pick.
///
/// All selection rules live here so the menu stays declarative:
/// - at most `maxCount` services
/// - TuneIn is exclusive (a radio directory doesn't merge into catalogs)
/// - unchecking the primary promotes the next selection
/// - the last service can't be removed
///
/// `RawRepresentable` (comma-separated raw values, order-preserving) lets
/// `@AppStorage` persist it while call sites work with real values.
struct SelectedSearchServices: RawRepresentable, Equatable {
    static let maxCount = 3

    private(set) var services: [MediaSearchService]

    var primary: MediaSearchService { services.first ?? .apple }
    var isAtLimit: Bool { services.count >= Self.maxCount }

    init(_ services: [MediaSearchService] = []) {
        self.services = services.isEmpty ? [.apple] : Array(services.prefix(Self.maxCount))
    }

    init(rawValue: String) {
        self.init(rawValue.split(separator: ",").compactMap { MediaSearchService(rawValue: String($0)) })
    }

    var rawValue: String {
        services.map(\.rawValue).joined(separator: ",")
    }

    func contains(_ service: MediaSearchService) -> Bool {
        services.contains(service)
    }

    mutating func toggle(_ service: MediaSearchService) {
        if service == .tuneIn {
            services = [.tuneIn]
            return
        }
        if primary == .tuneIn {
            // Leaving TuneIn: the tapped service becomes the sole selection.
            services = [service]
            return
        }
        if let index = services.firstIndex(of: service) {
            // Removing the first entry promotes the next; the last one stays.
            guard services.count > 1 else { return }
            services.remove(at: index)
        } else if !isAtLimit {
            services.append(service)
        }
    }

    /// Drops services disabled in Settings, falling back so the selection is
    /// never empty. No-ops (no storage write) when nothing is disabled.
    mutating func prune(isEnabled: (MediaSearchService) -> Bool, fallback: MediaSearchService) {
        guard services.contains(where: { !isEnabled($0) }) else { return }
        services.removeAll { !isEnabled($0) }
        if services.isEmpty {
            services = [fallback]
        }
    }
}
