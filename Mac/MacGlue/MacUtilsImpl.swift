//
//  MacUtilsImpl.swift
//  Clic
//
//  Created by Nick Hayward on 1/3/25.
//


//  KeePassium Password Manager
//  Copyright 2018-2024 KeePassium Labs <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact us.

import AppKit
import Carbon

class MacUtilsImpl: NSObject, MacUtils {
    var isRunning: Bool = false
    private let bundleIdentifier = "com.nick.clic.mini"  // Replace with your actual bundle identifier
    private var appsObserver: TopRunningAppsObserver?
    private var handler: ((Bool) -> Void)?

    required override init() {
        super.init()
    }
    
    func disableSecureEventInput() {
        print("Hello")
    }

    func isSecureEventInputEnabled() -> Bool {
        return false
    }

    func isControlKeyPressed() -> Bool {
        return (GetCurrentKeyModifiers() & UInt32(controlKey)) != 0
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
