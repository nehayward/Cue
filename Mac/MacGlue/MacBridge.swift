//
//  MacUtilsImpl.swift
//  Clic
//
//  CLICMINI LAUNCHER + RUNNING OBSERVER
//
//  The launcher uses NSWorkspace.OpenConfiguration to launch ClicMini. The app
//  is discovered by checking multiple standard locations in priority order:
//
//  1. System bundle identifier lookup (if previously launched)
//  2. Contents/PlugIns/ClicMini.app (current bundled location)
//  3. Contents/Library/LoginItems/ClicMini.app (Apple's standard helper apps)
//  4. Same directory as Clic.app (side-by-side installation)
//  5. /Applications/ClicMini.app
//
//  REQUIREMENTS:
//  - Both apps must share the same app group: "group.com.clic"
//  - ClicMini Info.plist must have LSUIElement = true (menu bar app)
//  - Both apps must be properly signed with the same team
//  - Both apps should be sandboxed with matching entitlements
//
//  Dock menu lives separately in DockMenuImpl. Access via `dockMenu`.
//

import AppKit
import ServiceManagement

final class MacBridge: NSObject, MacBridgeable, @unchecked Sendable {
    var isRunning: Bool = false
    private let bundleIdentifier = "com.nick.clic.mini"
    private var appsObserver: TopRunningAppsObserver?
    private var handler: ((Bool) -> Void)?

    /// Notification name for requesting ClicMini to show its menu
    static let showMenuNotification = Notification.Name("com.clic.mini.showMenu")

    private lazy var _dockMenu: DockMenuRenderer = DockMenuRenderer()
    var dockMenu: DockMenuRenderable { _dockMenu }

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
    }

    // MARK: - ClicMini launch

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

    /// Protocol-conforming async version (defaults to showing menu).
    func openClicMiniApp() async throws {
        try await openClicMiniApp(showMenu: true)
    }

    /// Opens ClicMini with option to show its dropdown menu.
    func openClicMiniApp(showMenu: Bool) async throws {
        let runningApps = NSWorkspace.shared.runningApplications
        if runningApps.first(where: { $0.bundleIdentifier == bundleIdentifier }) != nil {
            // Already running — post notification to show menu if asked.
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
        try await launchViaWorkspace(showMenu: showMenu)
    }

    /// Finds ClicMini.app by checking multiple standard locations.
    private func findClicMiniAppURL() throws -> URL {
        let fileManager = FileManager.default
        let mainBundleURL = Bundle.main.bundleURL

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
           fileManager.fileExists(atPath: url.path) {
            return url
        }

        let plugInsPath = mainBundleURL.appendingPathComponent("Contents/PlugIns/ClicMini.app")
        if fileManager.fileExists(atPath: plugInsPath.path) { return plugInsPath }

        let loginItemsPath = mainBundleURL.appendingPathComponent("Contents/Library/LoginItems/ClicMini.app")
        if fileManager.fileExists(atPath: loginItemsPath.path) { return loginItemsPath }

        let siblingPath = mainBundleURL.deletingLastPathComponent().appendingPathComponent("ClicMini.app")
        if fileManager.fileExists(atPath: siblingPath.path) { return siblingPath }

        let applicationsPath = URL(fileURLWithPath: "/Applications/ClicMini.app")
        if fileManager.fileExists(atPath: applicationsPath.path) { return applicationsPath }

        print("ClicMini not found. Searched locations:")
        print("  1. Bundle ID lookup: \(bundleIdentifier)")
        print("  2. PlugIns: \(plugInsPath.path)")
        print("  3. LoginItems: \(loginItemsPath.path)")
        print("  4. Sibling: \(siblingPath.path)")
        print("  5. Applications: \(applicationsPath.path)")

        throw ClicMiniError.appNotFound
    }

    private func launchViaWorkspace(showMenu: Bool = false) async throws {
        let appURL = try findClicMiniAppURL()
        print("Found ClicMini at: \(appURL.path)")

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.promptsUserIfNeeded = true
        configuration.addsToRecentItems = false
        configuration.hidesOthers = false
        configuration.hides = false
        if showMenu {
            configuration.arguments = ["--show-menu"]
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
                if let error = error {
                    continuation.resume(throwing: ClicMiniError.launchFailed(reason: error.localizedDescription))
                    return
                }
                if let app = app {
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

    // MARK: - Running observer

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
