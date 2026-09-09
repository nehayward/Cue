import Defaults
import Foundation
import Network
import Observation

/// Whether the app is working with only what's on this device: no network
/// at all — airplane mode, a dead spot — or the user's own switch, for
/// leaving the streaming library alone on a plane before the door closes.
///
/// While it's active the Home tab shows only what's downloaded, and every
/// Play goes to this device rather than a speaker none can reach.
///
/// Read off `shared` rather than the environment where a surface is hosted
/// outside what `withEnvironments()` installs; `@Observable` tracks the
/// reads either way.
@MainActor
@Observable
final class OfflineMode {
    static let shared = OfflineMode()

    /// The user's switch, kept across launches.
    var isOn: Bool {
        didSet { UserDefaults.standard.set(isOn, forKey: AppStorageKeys.offlineMode) }
    }

    /// Whether any network path is up. `NWPathMonitor` reports the current
    /// path as soon as it starts, so this is right from the first read.
    private(set) var hasNetwork = true

    /// Offline for either reason.
    var isActive: Bool { isOn || !hasNetwork }

    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        isOn = UserDefaults.standard.bool(forKey: AppStorageKeys.offlineMode)
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.hasNetwork = satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "dance.cue.offline.path", qos: .utility))
    }
}
