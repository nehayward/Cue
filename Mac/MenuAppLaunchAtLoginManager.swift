import Foundation
#if targetEnvironment(macCatalyst)
import ServiceManagement
#endif
import OSLog

#if targetEnvironment(macCatalyst)

@Observable
final class MenuAppLaunchAtLoginManager {
    @ObservationIgnored static var shared = MenuAppLaunchAtLoginManager()
    var isRunning: Bool = false
    var macUtils: MacUtils?

    var isLaunchAtLoginEnabled: Bool { SMAppService.menuApp.status == .enabled }
    
    init() {
        macUtils = Self.loadDelegate()
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
        macUtils?.setupRunningAppsObserver()
        macUtils?.runningUpdate(handler: { [weak self] isRunning in
            print("----Running-----")
            self?.isRunning = isRunning
        })
    }
    
    func stopMonitor() {
        macUtils?.stopRunningAppObserver()
    }
    
    static func loadDelegate() -> MacUtils? {
        let bundleFileName = "MacGlue.bundle"
        guard let bundleURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent(bundleFileName) else {
            print("Failed to find MacGlue plugin URL")
            return nil
        }
        
        guard let bundle = Bundle(url: bundleURL) else {
            print("Failed to create bundle from URL: \(bundleURL)")
            return nil
        }
        
        // Load bundle explicitly and handle errors
        do {
            try bundle.loadAndReturnError()
        } catch {
            print("Failed to load MacGlue bundle: \(error)")
            return nil
        }
        
        let className = "MacGlue.MacUtilsImpl"
        guard let pluginClass = bundle.classNamed(className) as? MacUtils.Type else {
            print("Failed to find MacUtilsImpl class in bundle")
            return nil
        }
        
        let macUtils = pluginClass.init()
        return macUtils
    }
}

@available(macOS 13.0, *)
private extension SMAppService {
    static let menuApp = SMAppService.loginItem(identifier: "com.nick.clic.mini")
}
#endif
