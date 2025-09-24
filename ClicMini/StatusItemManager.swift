import Combine
import SwiftUI
import SonosKitMini
import KeyboardShortcuts
import ServiceManagement

final class StatusItemManager {
    private lazy var menuBarViewHost = NSHostingView(rootView: MenuBarView(sizePassthrough: sizePassthrough))
    private var statusItem: NSStatusItem?
    
    private var sizePassthrough = PassthroughSubject<CGSize, Never>()
    private var sizePassthroughWindow = PassthroughSubject<CGSize, Never>()
    
    private var sizeCancellable: AnyCancellable?
    private var sizeCancellableWindow: AnyCancellable?
    private var status: StatusBarMenuWindowController?
    
    private let settingsService = MiniSettingsService.shared
    
    
    @objc func toggleUIVisible(_ sender: NSStatusBarButton) {
        if status?.window?.isVisible == false {
            status?.showWindow(self)
        }
    }
    
    
    func createStatusItem() {
        if statusItem != nil { return }
        let statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button!.target = self
        statusItem.button!.action = #selector(triggerStatus)
        statusItem.button!.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.image = NSImage(named: "clic.icon")?.withSymbolConfiguration(.init(pointSize: 32, weight: .black))
        
//        statusItem.button?.action = #selector(toggleUIVisible)
        
        
//        let contentView = GroupMenuScreen(sizePassthroughWindow: sizePassthroughWindow).environment(SonosMiniService.shared)
        
//        let contentView = GroupMenuScreen(sizePassthroughWindow: sizePassthroughWindow)
//        status = StatusBarMenuWindowController(
//            statusItem: statusItem,
//            view: contentView
//        )
        // MARK: SwiftUI Menubar View
        //        // Add the hosting view for SwiftUI content
//        statusItem.button?.frame = menuBarViewHost.frame
//        statusItem.button?.addSubview(menuBarViewHost)
//
//        sizeCancellable = sizePassthrough.sink { [weak self] size in
//            print("Sizing")
//            let frame = NSRect(origin: .zero, size: .init(width: size.width, height: 24))
//            self?.menuBarViewHost.frame = frame
//            self?.statusItem?.button?.frame = frame
//        }
        //
        //        self.hostingView = hostingView
        self.statusItem = statusItem
        sizeCancellableWindow = sizePassthroughWindow.sink { [weak self] size in
            print(" CHANGING SiZE WINDOW _______________")
            let frame = NSRect(origin: .zero, size: .init(width: size.width, height: size.height))
            self?.statusItem?.menu?.items.first?.view?.frame = frame
            print("------- HERE")
            print("-------", frame)
            
//
//            let height = min(frame.height, 800)
//            self?.status?.repositionWindow(height: height)
        }
        
        Task {
            await SonosMonitor.shared.startListening()
        }
    }
    
    
    @MainActor @objc private func triggerStatus(_ button: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        switch event.type {
        case .rightMouseUp:
            handleRightClick()
        case .leftMouseUp:
            toggleGroupMenu()
        default:
            break
        }
    }
    
    @MainActor private func handleRightClick() {
        let alternateMenu = NSMenu()
        
        let toggleClicMini = NSMenuItem()
        toggleClicMini.title = "Toggle Clic Mini"
        toggleClicMini.target = self
        toggleClicMini.action = #selector(toggleGroupMenu)
        toggleClicMini.setShortcut(for: .toggleClicMini)
        alternateMenu.addItem(toggleClicMini)
        
        // Add separator
        alternateMenu.addItem(NSMenuItem.separator())
        
        // Add Launch at Login item
        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = settingsService.launchAtLogin ? .on : .off
        alternateMenu.addItem(launchAtLoginItem)
        
        // Add Preferences item
        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        alternateMenu.addItem(preferencesItem)
        
        // Add separator before quit
        alternateMenu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        alternateMenu.addItem(quitItem)
        
        statusItem?.menu = alternateMenu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc private func toggleLaunchAtLogin() {
        Task { @MainActor in
            await settingsService.toggleLaunchAtLogin()
        }
    }
    
    @MainActor
    @objc private func openPreferences() {
        WindowManager.shared.openPreferences()
    }

    @objc func toggleGroupMenu() {
        if statusItem?.menu != nil {
            statusItem?.menu?.cancelTracking()
            statusItem?.menu = nil
        } else {
            let contentView = NSHostingView(rootView: GroupMenuScreen(sizePassthroughWindow: sizePassthroughWindow).environment(SonosMiniService.shared))
            
            let menu = NSMenu()
            let menuItem = NSMenuItem()
            menuItem.view = contentView
            menu.addItem(menuItem)
            
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        }
        
    }
}

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
