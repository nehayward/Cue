import Foundation
#if targetEnvironment(macCatalyst)
import ServiceManagement
#endif
import OSLog

#if targetEnvironment(macCatalyst)

@Observable
final class MenuAppLaunchAtLoginManager {
    
    @ObservationIgnored static var appKitController: NSObject?
    @ObservationIgnored private lazy var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: String(describing: Self.self))
    
    static var shared = MenuAppLaunchAtLoginManager()
    var isRunning: Bool = false
    var macUtils: MacUtils?

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
    
    func monitor() {
        macUtils?.setupRunningAppsObserver()
        macUtils?.runningUpdate(handler: { isRunning in
            print("----Running-----")
            self.isRunning = isRunning
        })
    }
    
    func stopMonitor() {
        macUtils?.stopRunningAppObserver()
    }
    
    func loadDelegate() {
        let bundleFileName = "MacGlue.bundle"
        guard let bundleURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent(bundleFileName) else {
//            Diag.error("Failed to find MacUtils plugin, macOS-specific functions will be limited")
            return
        }
        
        guard let bundle = Bundle(url: bundleURL) else {
//            Diag.error("Failed to load MacUtils plugin, macOS-specific functions will be limited")
            return
        }
        
        let className = "MacGlue.MacUtilsImpl"
        guard let pluginClass = bundle.classNamed(className) as? MacUtils.Type else {
            print("Failed to instantiate MacUtils plugin, macOS-specific functions will be limited")
            return
        }
        
        macUtils = pluginClass.init()
    }
}

@available(macOS 13.0, *)
private extension SMAppService {
    static let menuApp = SMAppService.loginItem(identifier: "com.nick.clic.mini")
}
#endif
