//
//  MacUtilsImpl.swift
//  Cue
//
//  CUEMINI LAUNCHER + RUNNING OBSERVER
//
//  The launcher uses NSWorkspace.OpenConfiguration to launch CueMini. The app
//  is discovered by checking multiple standard locations in priority order:
//
//  1. System bundle identifier lookup (if previously launched)
//  2. Contents/PlugIns/CueMini.app (current bundled location)
//  3. Contents/Library/LoginItems/CueMini.app (Apple's standard helper apps)
//  4. Same directory as Cue.app (side-by-side installation)
//  5. /Applications/CueMini.app
//
//  REQUIREMENTS:
//  - Both apps must share the same app group: "group.dance.cue"
//  - CueMini Info.plist must have LSUIElement = true (menu bar app)
//  - Both apps must be properly signed with the same team
//  - Both apps should be sandboxed with matching entitlements
//
//  Dock menu lives separately in DockMenuImpl. Access via `dockMenu`.
//

import AppKit
import ServiceManagement

final class MacBridge: NSObject, MacBridgeable, @unchecked Sendable {
    var isRunning: Bool = false
    private let bundleIdentifier = "dance.cue.mini"
    private var appsObserver: TopRunningAppsObserver?
    private var handler: ((Bool) -> Void)?

    /// Notification name for requesting CueMini to show its menu
    static let showMenuNotification = Notification.Name("com.cue.mini.showMenu")

    private lazy var _dockMenu: DockMenuRenderer = DockMenuRenderer()
    var dockMenu: DockMenuRenderable { _dockMenu }

    enum CueMiniError: LocalizedError {
        case appNotFound
        case launchFailed(reason: String)
        case invalidConfiguration

        var errorDescription: String? {
            switch self {
            case .appNotFound:
                return "CueMini app could not be found. Please ensure it is installed."
            case .launchFailed(let reason):
                return "Failed to launch CueMini: \(reason)"
            case .invalidConfiguration:
                return "Invalid launch configuration for CueMini."
            }
        }
    }

    required override init() {
        super.init()
    }

    // MARK: - CueMini launch

    func openCueMiniApp() {
        openCueMiniApp { result in
            switch result {
            case .success:
                print("CueMini app launched successfully")
            case .failure(let error):
                print("Failed to launch CueMini: \(error.localizedDescription)")
            }
        }
    }

    /// Protocol-conforming async version (defaults to showing menu).
    func openCueMiniApp() async throws {
        try await openCueMiniApp(showMenu: true)
    }

    /// Opens CueMini with option to show its dropdown menu.
    func openCueMiniApp(showMenu: Bool) async throws {
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

    /// Finds CueMini.app by checking multiple standard locations.
    private func findCueMiniAppURL() throws -> URL {
        let fileManager = FileManager.default
        let mainBundleURL = Bundle.main.bundleURL

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
           fileManager.fileExists(atPath: url.path) {
            return url
        }

        let plugInsPath = mainBundleURL.appendingPathComponent("Contents/PlugIns/CueMini.app")
        if fileManager.fileExists(atPath: plugInsPath.path) { return plugInsPath }

        let loginItemsPath = mainBundleURL.appendingPathComponent("Contents/Library/LoginItems/CueMini.app")
        if fileManager.fileExists(atPath: loginItemsPath.path) { return loginItemsPath }

        let siblingPath = mainBundleURL.deletingLastPathComponent().appendingPathComponent("CueMini.app")
        if fileManager.fileExists(atPath: siblingPath.path) { return siblingPath }

        let applicationsPath = URL(fileURLWithPath: "/Applications/CueMini.app")
        if fileManager.fileExists(atPath: applicationsPath.path) { return applicationsPath }

        print("CueMini not found. Searched locations:")
        print("  1. Bundle ID lookup: \(bundleIdentifier)")
        print("  2. PlugIns: \(plugInsPath.path)")
        print("  3. LoginItems: \(loginItemsPath.path)")
        print("  4. Sibling: \(siblingPath.path)")
        print("  5. Applications: \(applicationsPath.path)")

        throw CueMiniError.appNotFound
    }

    private func launchViaWorkspace(showMenu: Bool = false) async throws {
        let appURL = try findCueMiniAppURL()
        print("Found CueMini at: \(appURL.path)")

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
                    continuation.resume(throwing: CueMiniError.launchFailed(reason: error.localizedDescription))
                    return
                }
                if let app = app {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if app.isTerminated {
                            continuation.resume(throwing: CueMiniError.launchFailed(reason: "App terminated immediately after launch"))
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                } else {
                    continuation.resume(throwing: CueMiniError.launchFailed(reason: "No app instance returned"))
                }
            }
        }
    }

    // Enhanced version with completion handler for better error handling
    func openCueMiniApp(completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                try await openCueMiniApp()
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
