import Foundation
#if targetEnvironment(macCatalyst)
import ServiceManagement
#endif
import OSLog
import SonosKit

#if targetEnvironment(macCatalyst)

/// Owns the MacGlue bundle, ClicMini launch-at-login registration, and
/// running-process observation. Dock-menu logic lives separately in
/// `DockMenuCoordinator` — this class no longer knows about the dock.
@Observable
final class MenuAppLaunchAtLoginManager {
    @ObservationIgnored static var shared = MenuAppLaunchAtLoginManager()
    var isRunning: Bool = false
    var bridge: MacBridgeable?

    var isLaunchAtLoginEnabled: Bool { SMAppService.menuApp.status == .enabled }

    init() {
        bridge = Self.loadDelegate()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) async throws {
        if enabled {
            try SMAppService.menuApp.register()
        } else {
            try await SMAppService.menuApp.unregister()
        }
    }

    private var hasAutoEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: #function) }
        set {
            UserDefaults.standard.set(newValue, forKey: #function)
            UserDefaults.standard.synchronize()
        }
    }

    func autoEnableIfNeeded() {
        guard !hasAutoEnabled else { return }
        hasAutoEnabled = true
        print(SMAppService.menuApp.status.rawValue)
        print("Attempting to auto-enable launch at login")

        Task {
            do {
                try await setLaunchAtLoginEnabled(true)
                print("Success")
            } catch {
                print(error)
            }
        }
    }

    func monitor() {
        bridge?.setupRunningAppsObserver()
        bridge?.runningUpdate(handler: { [weak self] isRunning in
            print("----Running-----")
            self?.isRunning = isRunning
        })
    }

    func stopMonitor() {
        bridge?.stopRunningAppObserver()
    }

    static func loadDelegate() -> MacBridgeable? {
        let bundleFileName = "MacGlue.bundle"
        guard let bundleURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent(bundleFileName) else {
            print("Failed to find MacGlue plugin URL")
            return nil
        }

        guard let bundle = Bundle(url: bundleURL) else {
            print("Failed to create bundle from URL: \(bundleURL)")
            return nil
        }

        do {
            try bundle.loadAndReturnError()
        } catch {
            print("Failed to load MacGlue bundle: \(error)")
            return nil
        }

        let className = "MacGlue.MacBridge"
        guard let pluginClass = bundle.classNamed(className) as? MacBridgeable.Type else {
            print("Failed to find MacBridge class in bundle")
            return nil
        }

        return pluginClass.init()
    }
}

@available(macOS 13.0, *)
private extension SMAppService {
    static let menuApp = SMAppService.loginItem(identifier: "com.nick.clic.mini")
}
#endif
