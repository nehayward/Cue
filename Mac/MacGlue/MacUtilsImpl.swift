//
//  MacUtilsImpl.swift
//  Clic
//
//  Created by Nick Hayward on 1/3/25.
//
//  MODERN IMPLEMENTATION FOR LAUNCHING CLICMINI
//
//  This implementation uses the modern NSWorkspace.OpenConfiguration API
//  combined with SMAppService for reliable cross-app launching.
//
//  REQUIREMENTS FOR SUCCESS:
//  1. Both apps must share the same app group: "group.com.clic"
//  2. ClicMini Info.plist must have LSUIElement = true (menu bar app)
//  3. Both apps must be properly signed with the same team
//  4. ClicMini must be registered as a login item via SMAppService
//  5. Both apps should be sandboxed with matching entitlements
//
//  TROUBLESHOOTING:
//  - If ClicMini doesn't launch, check Console.app for crash logs
//  - Verify ClicMini.app exists in the same directory as Clic.app
//  - Ensure bundle identifier "com.nick.clic.mini" is correct
//  - Check that SMAppService.menuApp.status shows .enabled or .requiresApproval
//

import AppKit
import ServiceManagement

class MacUtilsImpl: NSObject, MacUtils, @unchecked Sendable {
    var isRunning: Bool = false
    private let bundleIdentifier = "com.nick.clic.mini"
    private let urlScheme = "clicmini://"
    private var appsObserver: TopRunningAppsObserver?
    private var handler: ((Bool) -> Void)?
    
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
    
    // Modern async/await version with throwing support
    func openClicMiniApp() async throws {
        // Check if app is already running
        let runningApps = NSWorkspace.shared.runningApplications
        if let existingApp = runningApps.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            // For menu bar apps, just ensure they're running - no need to activate
            // activate() without options is the modern approach in macOS 14+
            _ = existingApp.activate()
            return
        }
        
        // Try Method 1: NSWorkspace with bundle identifier
        do {
            try await launchViaWorkspace()
            return
        } catch {
            print("NSWorkspace launch failed: \(error.localizedDescription), trying URL scheme fallback")
        }
        
        // Try Method 2: URL Scheme fallback
        if let url = URL(string: urlScheme) {
            let opened = NSWorkspace.shared.open(url)
            if opened {
                return
            }
        }
        
        throw ClicMiniError.launchFailed(reason: "All launch methods failed")
    }
    
    private func launchViaWorkspace() async throws {
        // Find the app URL - try multiple methods for reliability
        var appURL: URL?
        
        // Method 1: Use bundle identifier lookup
        appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        
        
        
        // Method 2: If not found, try looking in the main app bundle
        if appURL == nil {
            let mainBundle = Bundle.main.bundleURL
            let possiblePath = mainBundle
                .deletingLastPathComponent()
                .appendingPathComponent("ClicMini.app")
            if FileManager.default.fileExists(atPath: possiblePath.path) {
                appURL = possiblePath
            }
        }
        
        guard let appURL = appURL else {
            throw ClicMiniError.appNotFound
        }
        
        // Configure launch options
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.promptsUserIfNeeded = true
        configuration.addsToRecentItems = false
        configuration.hidesOthers = false
        configuration.hides = false
        
        
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
