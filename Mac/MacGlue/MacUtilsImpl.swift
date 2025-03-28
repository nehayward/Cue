//
//  MacUtilsImpl.swift
//  Clic
//
//  Created by Nick Hayward on 1/3/25.
//

import AppKit

class MacUtilsImpl: NSObject, MacUtils {
    var isRunning: Bool = false
    private let bundleIdentifier = "com.nick.clic.mini"  // Replace with your actual bundle identifier
    private var appsObserver: TopRunningAppsObserver?
    private var handler: ((Bool) -> Void)?

    required override init() {
        super.init()
    }
    
    func isControlKeyPressed() -> Bool {
//        return (GetCurrentKeyModifiers() & UInt32(controlKey)) != 0
        return false
    }
    
    // Added function to open ClicMini app
    func openClicMiniApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else {
            print("ClicMini app not found")
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
