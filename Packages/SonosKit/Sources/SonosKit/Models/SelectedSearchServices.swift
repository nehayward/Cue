import Foundation
import MusicSearchKit

/// The search's selected services as ONE ordered list — primary first, up to
/// `maxCount`. Replaces the old split storage (primary in `mediaService`,
/// extras in `searchAlsoServices`); old values are deliberately not migrated,
/// the selection resets once and users re-pick.
///
/// All selection rules live here (unit-tested in SonosKitTests) so the menu
/// stays declarative:
/// - at most `maxCount` services
/// - TuneIn is exclusive (a radio directory doesn't merge into catalogs)
/// - unchecking the primary promotes the next selection
/// - the last service can't be removed
///
/// `RawRepresentable` (comma-separated raw values, order-preserving) lets
/// `@AppStorage` persist it while call sites work with real values.
public struct SelectedSearchServices: RawRepresentable, Equatable, Sendable {
    public static let maxCount = 3

    public private(set) var services: [MediaSearchService]

    public var primary: MediaSearchService { services.first ?? .apple }
    public var isAtLimit: Bool { services.count >= Self.maxCount }

    public init(_ services: [MediaSearchService] = []) {
        // Storage is only written by this type, but stored strings survive
        // app versions — dedupe and cap defensively rather than trusting them.
        var seen = Set<MediaSearchService>()
        let unique = services.filter { seen.insert($0).inserted }
        self.services = unique.isEmpty ? [.apple] : Array(unique.prefix(Self.maxCount))
    }

    public init(rawValue: String) {
        self.init(rawValue.split(separator: ",").compactMap { MediaSearchService(rawValue: String($0)) })
    }

    public var rawValue: String {
        services.map(\.rawValue).joined(separator: ",")
    }

    public func contains(_ service: MediaSearchService) -> Bool {
        services.contains(service)
    }

    public mutating func toggle(_ service: MediaSearchService) {
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
    public mutating func prune(isEnabled: (MediaSearchService) -> Bool, fallback: MediaSearchService) {
        guard services.contains(where: { !isEnabled($0) }) else { return }
        services.removeAll { !isEnabled($0) }
        if services.isEmpty {
            services = [fallback]
        }
    }
}
