import Foundation
#if targetEnvironment(macCatalyst)
import ServiceManagement
#endif
import OSLog

#if targetEnvironment(macCatalyst)

@Observable
final class MenuAppLaunchAtLoginManager {
    @ObservationIgnored private lazy var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: String(describing: Self.self))
    
    static var shared = MenuAppLaunchAtLoginManager()

    var isLaunchAtLoginEnabled: Bool { SMAppService.menuApp.status == .enabled }

    func setLaunchAtLoginEnabled(_ enabled: Bool) async throws {
        logger.debug("Set launch at login enabled: \(enabled, privacy: .public)")

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

}

@available(macOS 13.0, *)
private extension SMAppService {
    static let menuApp = SMAppService.loginItem(identifier: "com.nick.ClicMenuApp")
}
#endif
