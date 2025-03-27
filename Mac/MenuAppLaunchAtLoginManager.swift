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
            logger.error("Failed to find MacUtils plugin path")
            return
        }
        
        do {
            guard let bundle = Bundle(url: bundleURL) else {
                logger.error("Failed to create bundle from URL: \(bundleURL.path)")
                return
            }
            
            // Load the bundle with error handling
            try bundle.loadAndReturnError()
            
            let className = "MacGlue.MacUtilsImpl"
            guard let pluginClass = bundle.classNamed(className) as? MacUtils.Type else {
                logger.error("Failed to instantiate MacUtils plugin class")
                return
            }
            
            macUtils = pluginClass.init()
            logger.debug("Successfully loaded MacUtils plugin")
        } catch {
            logger.error("Failed to load MacUtils plugin: \(error.localizedDescription)")
        }
    }
}

@available(macOS 13.0, *)
private extension SMAppService {
    static let menuApp = SMAppService.loginItem(identifier: "com.nick.clic.mini")
}
#endif
