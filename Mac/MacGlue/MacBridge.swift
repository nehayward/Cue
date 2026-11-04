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
import CoreServices
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

    // MARK: - One development copy

    /// Copies built in DerivedData only, so an installed Cue is left alone. One
    /// built by a script goes if Xcode's is running, as the one the listener is
    /// using; otherwise the newest stays. Xcode only stops copies it started.
    ///
    /// The others are asked to quit themselves: a sandboxed app can't terminate
    /// another.
    func keepOneDevelopmentCopy() {
        let pid = String(getpid())
        // Xcode's own folder for a project is its name and a hash.
        func isXcodeBuilt(_ path: String?) -> Bool {
            path?.range(of: "/DerivedData/[^/]+-[a-z]{28}/", options: .regularExpression) != nil
        }
        let others = Bundle.main.bundleIdentifier.map(NSRunningApplication.runningApplications(withBundleIdentifier:))?.filter {
            $0.processIdentifier != getpid() && $0.bundleURL?.path.contains("/DerivedData/") == true
        } ?? []
        if !isXcodeBuilt(Bundle.main.bundlePath), let xcode = others.first(where: { isXcodeBuilt($0.bundleURL?.path) }) {
            xcode.activate()
            exit(0)
        }

        observeDistributedNotification(named: Self.quitCopiesNotification) { sender in
            guard sender != pid else { return }
            NSApp.terminate(nil)
        }
        guard !others.isEmpty else { return }
        postDistributedNotification(named: Self.quitCopiesNotification, object: pid)
        // They've let go of the Sonos event port before this one asks for it.
        let deadline = Date.now.addingTimeInterval(2)
        while others.contains(where: { !$0.isTerminated }), Date.now < deadline {
            RunLoop.current.run(until: .now + 0.1)
        }
    }

    private static let quitCopiesNotification = "dance.cue.debug.quitOtherCopies"

    // MARK: - Running observer

    var isCueMiniRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

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

    // MARK: - Dictionary

    func definition(of term: String) -> String? {
        let text = term as CFString
        let range = CFRange(location: 0, length: CFStringGetLength(text))
        guard range.length > 0, let definition = DCSCopyTextDefinition(nil, text, range) else { return nil }
        return definition.takeRetainedValue() as String
    }

    // MARK: - About

    func showAboutPanel(credits: String, links: [String: String]) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = NSMutableAttributedString(string: credits, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ])
        for (phrase, link) in links {
            let range = (credits as NSString).range(of: phrase)
            guard range.location != NSNotFound, let url = URL(string: link) else { continue }
            text.addAttribute(.link, value: url, range: range)
        }
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: text])
    }

    // MARK: - Window material

    private static let materialIdentifier = NSUserInterfaceItemIdentifier("dance.cue.sidebarMaterial")

    /// The main window: titled `title` and with no toolbar. A Settings
    /// window reopened at launch can be titled for the app a moment before
    /// its pane names it, and took the main window's close button with it;
    /// its toolbar it has from the start.
    private func mainWindows(titled title: String) -> [NSWindow] {
        NSApp.windows.filter { $0.title == title && $0.toolbar == nil }
    }

    func installSidebarMaterial(inWindowsTitled title: String) {
        for window in mainWindows(titled: title) {
            // The window's frame view, not its content view, which starts
            // below the title bar and left a dark strip under the traffic
            // lights.
            guard let frame = window.contentView?.superview,
                  !frame.subviews.contains(where: { $0.identifier == Self.materialIdentifier }) else { continue }
            window.titlebarAppearsTransparent = true
            let material = NSVisualEffectView(frame: frame.bounds)
            material.material = .sidebar
            material.blendingMode = .behindWindow
            material.state = .followsWindowActiveState
            material.identifier = Self.materialIdentifier
            material.autoresizingMask = [.width, .height]
            frame.addSubview(material, positioned: .below, relativeTo: nil)
            // Liquid Glass over it, where the system has it: the blurred
            // desktop refracted, lit at its edges.
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView(frame: frame.bounds)
                glass.style = .clear
                glass.autoresizingMask = [.width, .height]
                frame.addSubview(glass, positioned: .above, relativeTo: material)
            }
        }
    }

    func hideOnClose(windowsTitled title: String) {
        for window in mainWindows(titled: title) {
            guard let button = window.standardWindowButton(.closeButton),
                  button.action != #selector(hideApp) else { continue }
            button.target = self
            button.action = #selector(hideApp)
        }
    }

    @objc func hideApp() {
        NSApp.hide(nil)
    }

    // MARK: - Distributed notifications

    /// The handler for each name observed.
    private var distributedHandlers: [String: (String?) -> Void] = [:]

    func postDistributedNotification(named name: String, object: String?) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(name),
            object: object,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    func observeDistributedNotification(named name: String, handler: @escaping (String?) -> Void) {
        let isNew = distributedHandlers[name] == nil
        distributedHandlers[name] = handler
        guard isNew else { return }
        // Delivered immediately: AppKit suspends distributed notifications
        // while an app isn't active, which Cue isn't while its menu bar app
        // is being used.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(receiveDistributedNotification(_:)),
            name: Notification.Name(name),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func receiveDistributedNotification(_ notification: Notification) {
        let object = notification.object as? String
        let name = notification.name.rawValue
        if Thread.isMainThread {
            distributedHandlers[name]?(object)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.distributedHandlers[name]?(object)
            }
        }
    }
}
