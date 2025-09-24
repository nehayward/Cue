import Cocoa
import SwiftUI

//class KeyboardShortcutHostingView<Content>: NSHostingView<Content> where Content: View {
//    override var acceptsFirstResponder: Bool { true }
//    
//    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
//        return true
//    }
//}

@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()
    
    private var preferencesWindowController: NSWindowController?
    
    private override init() {}
    
    func openPreferences() {
        if let existingWindow = preferencesWindowController?.window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        let preferencesView = MiniSettingsView()
        let hostingView = NSHostingView(rootView: preferencesView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Clic Mini Preferences"
        window.contentView = hostingView
        window.center()
        window.setFrameAutosaveName("PreferencesWindow")
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.delegate = self
        
        preferencesWindowController = NSWindowController(window: window)
        preferencesWindowController?.showWindow(nil)
        
        // Set to regular app for proper text input handling
        NSApp.setActivationPolicy(.regular)
        
        // Setup minimal menu for Command+W support
        setupMinimalMenu()
        
        // Ensure the app is activated and window gets focus
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    
    func closePreferences() {
        preferencesWindowController?.close()
        preferencesWindowController = nil
        
        // Reset to accessory app (menu bar app behavior)
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setupMinimalMenu() {
        let mainMenu = NSMenu()
        
        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        
        // Close window menu item with Command+W
        let closeItem = NSMenuItem(title: "Close Window", action: #selector(closeWindowFromMenu), keyEquivalent: "w")
        closeItem.target = self
        appMenu.addItem(closeItem)
        
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        NSApp.mainMenu = mainMenu
    }
    
    @objc private func closeWindowFromMenu() {
        closePreferences()
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        // Reset to accessory app when window is closed by any means
        NSApp.setActivationPolicy(.accessory)
        preferencesWindowController = nil
    }
}
