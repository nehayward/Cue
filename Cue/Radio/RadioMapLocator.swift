import CoreLocation
import OSLog

/// Where this device is, for the Radio map's Stations Near You. Asked only
/// when that button is tapped: the first tap brings up the system's prompt,
/// and each tap takes one fix rather than following the device. A rough fix
/// is plenty, since TuneIn's local page covers a whole metro area, so
/// Approximate Location does as well as Precise.
@MainActor
final class RadioMapLocator: NSObject, CLLocationManagerDelegate {
    enum Outcome {
        case found(CLLocationCoordinate2D)
        /// Location is off for Cue, or for the whole device. The prompt
        /// doesn't come again, so only Settings can turn it on.
        case denied
        /// Allowed, but no fix came (Airplane Mode, deep indoors).
        case unavailable
    }

    private let manager = CLLocationManager()
    private var decision: CheckedContinuation<Void, Never>?
    private var fix: CheckedContinuation<CLLocation?, Never>?

    private static let log = Logger(subsystem: "dance.cue", category: "radioMap")

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Asks for permission if it was never asked, then for one fix.
    func currentLocation() async -> Outcome {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                decision = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        default:
            Self.log.notice("location: not allowed")
            return .denied
        }

        let location = await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            fix = continuation
            manager.requestLocation()
        }
        guard let location else { return .unavailable }
        Self.log.notice("location: found, to within \(Int(location.horizontalAccuracy)) m")
        return .found(location.coordinate)
    }

    // Called on the main thread: the manager was made there.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            // Also called as the manager starts, before the prompt is answered.
            guard manager.authorizationStatus != .notDetermined else { return }
            decision?.resume()
            decision = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            fix?.resume(returning: locations.last)
            fix = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            Self.log.notice("location: failed: \(error.localizedDescription, privacy: .public)")
            fix?.resume(returning: nil)
            fix = nil
        }
    }
}
