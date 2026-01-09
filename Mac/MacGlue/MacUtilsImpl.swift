//
//  MacUtilsImpl.swift
//  Clic
//
//  Created by Nick Hayward on 1/3/25.
//
//  CLICMINI LAUNCHER IMPLEMENTATION
//
//  This implementation uses NSWorkspace.OpenConfiguration to launch ClicMini.
//  The app is discovered by checking multiple standard locations in priority order.
//
//  CLICMINI LOCATIONS (checked in order):
//  1. System bundle identifier lookup (if previously launched)
//  2. Contents/PlugIns/ClicMini.app (current bundled location)
//  3. Contents/Library/LoginItems/ClicMini.app (Apple's standard for helper apps)
//  4. Same directory as Clic.app (side-by-side installation)
//  5. /Applications/ClicMini.app
//
//  REQUIREMENTS:
//  1. Both apps must share the same app group: "group.com.clic"
//  2. ClicMini Info.plist must have LSUIElement = true (menu bar app)
//  3. Both apps must be properly signed with the same team
//  4. Both apps should be sandboxed with matching entitlements
//
//  TROUBLESHOOTING:
//  - If ClicMini doesn't launch, check Console.app for crash logs
//  - Verify ClicMini.app exists in one of the searched locations
//  - Ensure bundle identifier "com.nick.clic.mini" is correct
//  - Check the console output for "ClicMini not found" with searched paths
//

import AppKit
import ServiceManagement

class MacUtilsImpl: NSObject, MacUtils, @unchecked Sendable {
    var isRunning: Bool = false
    private let bundleIdentifier = "com.nick.clic.mini"
    private var appsObserver: TopRunningAppsObserver?
    private var handler: ((Bool) -> Void)?

    /// Notification name for requesting ClicMini to show its menu
    static let showMenuNotification = Notification.Name("com.clic.mini.showMenu")
    
    enum ClicMiniError: LocalizedError {
        case appNotFound
        case launchFailed(reason: String)
        case invalidConfiguration
        
        var errorDescription: String? {
            switch self {
            case .appNotFound:
                return "ClicMini app could not be found. Please ensure it is installed."
            case .launchFailed(let reason):
                return "Failed to launch ClicMini: \(reason)"
            case .invalidConfiguration:
                return "Invalid launch configuration for ClicMini."
            }
        }
    }

    required override init() {
        super.init()
//        // MARK: Hide Tool bar need to migrate everything over.
//        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
//            NSApplication.shared.mainWindow!.titlebarAppearsTransparent = true
//        }
    }
    
    func isControlKeyPressed() -> Bool {
//        return (GetCurrentKeyModifiers() & UInt32(controlKey)) != 0
        return false
    }
    
    // Added function to open ClicMini app with comprehensive error handling
    func openClicMiniApp() {
        openClicMiniApp { result in
            switch result {
            case .success:
                print("ClicMini app launched successfully")
            case .failure(let error):
                print("Failed to launch ClicMini: \(error.localizedDescription)")
            }
        }
    }
    
    // Protocol-conforming async version (defaults to showing menu)
    func openClicMiniApp() async throws {
        try await openClicMiniApp(showMenu: true)
    }

    /// Opens ClicMini with option to show its dropdown menu
    /// - Parameter showMenu: If true, requests ClicMini to show its dropdown menu after launching
    func openClicMiniApp(showMenu: Bool) async throws {
        // Check if app is already running
        let runningApps = NSWorkspace.shared.runningApplications
        if runningApps.first(where: { $0.bundleIdentifier == bundleIdentifier }) != nil {
            // App is already running - post notification to show menu
            if showMenu {
                DistributedNotificationCenter.default().postNotificationName(
                    Self.showMenuNotification,
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true
                )
            }
            return
        }

        // Launch via NSWorkspace - this handles all path resolution
        try await launchViaWorkspace(showMenu: showMenu)
    }
    
    /// Finds ClicMini.app by checking multiple standard locations
    /// Priority order:
    /// 1. System bundle identifier lookup (if ClicMini is properly registered)
    /// 2. Contents/PlugIns/ (current bundled location)
    /// 3. Contents/Library/LoginItems/ (Apple's standard for helper apps)
    /// 4. Same directory as main app (side-by-side installation)
    /// 5. /Applications folder
    private func findClicMiniAppURL() throws -> URL {
        let fileManager = FileManager.default
        let mainBundleURL = Bundle.main.bundleURL

        // Method 1: System bundle identifier lookup
        // This works if ClicMini was previously launched or is registered
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        // Method 2: PlugIns folder (current bundled location)
        let plugInsPath = mainBundleURL
            .appendingPathComponent("Contents/PlugIns/ClicMini.app")
        if fileManager.fileExists(atPath: plugInsPath.path) {
            return plugInsPath
        }

        // Method 3: Standard location for helper/login item apps
        let loginItemsPath = mainBundleURL
            .appendingPathComponent("Contents/Library/LoginItems/ClicMini.app")
        if fileManager.fileExists(atPath: loginItemsPath.path) {
            return loginItemsPath
        }

        // Method 4: Same directory as main app (side-by-side installation)
        let siblingPath = mainBundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("ClicMini.app")
        if fileManager.fileExists(atPath: siblingPath.path) {
            return siblingPath
        }

        // Method 5: /Applications folder
        let applicationsPath = URL(fileURLWithPath: "/Applications/ClicMini.app")
        if fileManager.fileExists(atPath: applicationsPath.path) {
            return applicationsPath
        }

        // Log all attempted paths for debugging
        print("ClicMini not found. Searched locations:")
        print("  1. Bundle ID lookup: \(bundleIdentifier)")
        print("  2. PlugIns: \(plugInsPath.path)")
        print("  3. LoginItems: \(loginItemsPath.path)")
        print("  4. Sibling: \(siblingPath.path)")
        print("  5. Applications: \(applicationsPath.path)")

        throw ClicMiniError.appNotFound
    }

    private func launchViaWorkspace(showMenu: Bool = false) async throws {
        // Find the app URL - try multiple methods for reliability
        let appURL = try findClicMiniAppURL()
        print("Found ClicMini at: \(appURL.path)")

        // Configure launch options
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.promptsUserIfNeeded = true
        configuration.addsToRecentItems = false
        configuration.hidesOthers = false
        configuration.hides = false

        // Pass --show-menu argument if requested
        if showMenu {
            configuration.arguments = ["--show-menu"]
        }
        
        
        // Attempt to launch the app using async continuation
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
                if let error = error {
                    continuation.resume(throwing: ClicMiniError.launchFailed(reason: error.localizedDescription))
                    return
                }
                
                if let app = app {
                    // Give the app a moment to initialize, then verify it's running
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if app.isTerminated {
                            continuation.resume(throwing: ClicMiniError.launchFailed(reason: "App terminated immediately after launch"))
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                } else {
                    continuation.resume(throwing: ClicMiniError.launchFailed(reason: "No app instance returned"))
                }
            }
        }
    }
    
    // Enhanced version with completion handler for better error handling
    func openClicMiniApp(completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                try await openClicMiniApp()
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    // Add private helper methods
    func setupRunningAppsObserver() {
        appsObserver = TopRunningAppsObserver(bundleIdentifier: bundleIdentifier)
        appsObserver?.start { [weak self] isRunning in
            self?.isRunning = isRunning
            self?.handler?(isRunning)
        }
    }
    
    func stopRunningAppObserver() {
        appsObserver?.stop()
        appsObserver = nil
    }
    
    func runningUpdate(handler: @escaping (Bool) -> Void) {
        self.handler = handler
    }
}
